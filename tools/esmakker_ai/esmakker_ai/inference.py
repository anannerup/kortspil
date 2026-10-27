"""One inference process for all the actors (config actor_inference
"server"; SEED RL style). Anders: a high actor count without the swap file,
and `import torch` alone commits ~1.4 GB per process (with CUDA ~2-2.4 GB).

The actors import no torch: they play the spil (the engine, Svær, the
search, features.encode and candidates) and hand every batch of decisions
to the inference process, which holds the net on actor_device, scores the
waiting batches of all actors in one forward pass (net.score_arrays, the
same computation as an actor's own net.score_requests) and hands back each
candidate's Q and each decision's best candidate.

Each actor has a block of shared memory (Buffers) with room for MAX_STATES
decisions and MAX_CANDS candidates: the actor writes its states (bytes),
candidate counts and candidate ids there, puts (actor id, decisions,
candidates) on the request queue and waits on its semaphore; the server
reads the block, writes Q and the best indices back and releases the
semaphore. Only those three ints are pickled per request. The weights come
from the learner as they did to the actors (a shared model, a version
number and a lock).

Within one forward pass the decisions do not see each other, so the
results are the actor's own path's: with one actor the samples are equal to
the in-process path (tests/test_inference.py). With several, a batch holds
several actors' decisions and its shape differs, which can move a Q in its
last float bits, as a different mix of runder in one actor's batch does.
"""

import queue as queue_module
from multiprocessing import shared_memory

import numpy as np

from . import features as F

MAX_STATES = 16384   # decisions in one request (measured: at most ~1 600 at 128 spil with search)
MAX_CANDS = 262144   # ... and candidates (~16 000)


def _layout(max_states, max_cands):
    """(name, dtype, shape, offset) of each array in a block, and its size."""
    arrays = (("states", np.uint8, (max_states, F.STATE_BYTES)), ("counts", np.int64, (max_states,)),
              ("cands", np.int16, (max_cands,)), ("q", np.float32, (max_cands,)), ("best", np.int64, (max_states,)))
    out, offset = [], 0
    for name, dtype, shape in arrays:
        out.append((name, dtype, shape, offset))
        offset += -(-int(np.prod(shape)) * np.dtype(dtype).itemsize // 64) * 64
    return out, offset


def buffer_size(max_states=MAX_STATES, max_cands=MAX_CANDS):
    return _layout(max_states, max_cands)[1]


class Buffers:
    """The numpy arrays over one actor's shared memory block."""

    def __init__(self, buf, max_states=MAX_STATES, max_cands=MAX_CANDS):
        self.max_states, self.max_cands = max_states, max_cands
        for name, dtype, shape, offset in _layout(max_states, max_cands)[0]:
            setattr(self, name, np.ndarray(shape, dtype, buffer=buf, offset=offset))


class ClientSpec:
    """What an actor needs to reach the server (picklable for the actor
    process): its id, its block's name, the request queue, its semaphore."""

    def __init__(self, actor_id, name, requests, done, max_states=MAX_STATES, max_cands=MAX_CANDS):
        self.actor_id, self.name, self.requests, self.done = actor_id, name, requests, done
        self.max_states, self.max_cands = max_states, max_cands


class Stopped(Exception):
    """The run stopped while an actor waited for the server."""


class RemoteScorer:
    """An actor's scorer (as actor.LocalScorer): scorer(states, cands) ->
    (every candidate's Q, each decision's best index), computed by the
    server. The results are copies: the block is overwritten by the next
    request (the search scores its belief while the step's Q are in use)."""

    def __init__(self, spec, stop_event):
        self.spec, self.stop_event = spec, stop_event
        self.shm = shared_memory.SharedMemory(name=spec.name)
        self.buffers = Buffers(self.shm.buf, spec.max_states, spec.max_cands)
        self.max_states, self.max_cands = spec.max_states, spec.max_cands  # a larger request is split

    def __call__(self, states, cands):
        n = len(states)
        counts = np.fromiter((len(c) for c in cands), np.int64, n)
        total = int(counts.sum())
        if n > self.max_states or total > self.max_cands:
            # more than the block holds (never measured): in two halves
            half = n // 2
            q1, best1 = self(states[:half], cands[:half])
            q2, best2 = self(states[half:], cands[half:])
            return np.concatenate([q1, q2]), np.concatenate([best1, best2])
        b = self.buffers
        b.states[:n] = np.frombuffer(b"".join(states), np.uint8).reshape(n, F.STATE_BYTES)
        b.counts[:n] = counts
        b.cands[:total] = np.fromiter((a for c in cands for a in c), np.int16, total)
        self.spec.requests.put((self.spec.actor_id, n, total))
        while not self.spec.done.acquire(timeout=0.5):
            if self.stop_event.is_set():
                raise Stopped()
        return b.q[:total].copy(), b.best[:n].copy()


def score_pending(model, actions, device, buffers, pending):
    """Scores the pending requests [(actor id, decisions, candidates)] of
    the actors' blocks in one forward pass and writes each its results."""
    from .net import score_arrays
    packed = np.concatenate([buffers[a].states[:n] for a, n, _ in pending])
    counts = np.concatenate([buffers[a].counts[:n] for a, n, _ in pending])
    flat = np.concatenate([buffers[a].cands[:c] for a, _, c in pending]).astype(np.int64)
    q, best = score_arrays(model, actions, device, packed, counts, flat)
    n0 = c0 = 0
    for a, n, c in pending:
        buffers[a].q[:c] = q[c0:c0 + c]
        buffers[a].best[:n] = best[n0:n0 + n]
        n0, c0 = n0 + n, c0 + c


def serve(config, shared_model, version, lock, requests, specs, dones, stop_event, stats=None):
    """The inference process (or a thread, in tests): the net on
    actor_device, the learner's weights whenever they change, and one
    forward pass per gathering of waiting requests until stop_event.
    specs: [(block name, max states, max cands)] by actor id; dones: the
    actors' semaphores. stats (a dict, threads only) counts the passes."""
    import torch

    from .actor import lower_priority
    from .agent import ACTION_TABLE
    from .net import build, pick_device
    if config.low_priority and stats is None:
        lower_priority()
    torch.set_num_threads(1)
    device = pick_device(config.actor_device)
    model = build(config).to(device)
    model.eval()
    actions = torch.from_numpy(ACTION_TABLE).to(device)
    blocks = [shared_memory.SharedMemory(name=name) for name, _, _ in specs]
    buffers = [Buffers(shm.buf, s, c) for shm, (_, s, c) in zip(blocks, specs)]
    seen = -1
    try:
        while not stop_event.is_set():
            if version.value != seen:
                with lock:
                    seen = version.value
                    model.load_state_dict(shared_model.state_dict())
            try:
                pending = [requests.get(timeout=0.2)]
            except queue_module.Empty:
                continue
            while len(pending) < len(buffers):
                try:
                    pending.append(requests.get_nowait())
                except queue_module.Empty:
                    break
            score_pending(model, actions, device, buffers, pending)
            for a, _, _ in pending:
                dones[a].release()
            if stats is not None:
                stats["passes"] = stats.get("passes", 0) + 1
                stats["requests"] = stats.get("requests", 0) + len(pending)
    finally:
        del buffers
        for shm in blocks:
            try:
                shm.close()
            except BufferError:  # a view still alive; the process ends anyway
                pass
