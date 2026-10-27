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
candidate counts and candidate ids there, puts (actor id, SCORE, decisions,
candidates) on the request queue and waits on its semaphore; the server
reads the block, writes Q and the best indices back and releases the
semaphore. Only those four ints are pickled per request. With
search_gpu_rollouts the block also holds up to MAX_BRANCHES rollouts
exported by tbranch (a ROLLOUT request): the server plays them out on the
GPU (trollout.Rollouts, all actors' branches in one batch) and writes back
their runde points. The weights come
from the learner as they did to the actors (a shared model, a version
number and a lock).

Within one forward pass the decisions do not see each other, so the
results are the actor's own path's: with one actor the samples are equal to
the in-process path (tests/test_inference.py). With several, a batch holds
several actors' decisions and its shape differs, which can move a Q in its
last float bits, as a different mix of runder in one actor's batch does.
"""

import queue as queue_module
import threading
import time
from multiprocessing import shared_memory

import numpy as np

from . import features as F

MAX_STATES = 16384   # decisions in one request (measured: at most ~1 600 at 128 spil with search)
MAX_CANDS = 262144   # ... and candidates (~16 000)
MAX_BRANCHES = 4096  # rollouts for the GPU in one request (search_gpu_rollouts)

SCORE, ROLLOUT = 0, 1  # a request: (actor id, SCORE, decisions, candidates) or (actor id, ROLLOUT, branches, statics)

# tbranch.branch_arrays' arrays: (name, dtype, shape of a row)
BRANCH_FIELDS = (("hands", "<u8", (4,)), ("played", "<u8", (4,)), ("void", bool, (16,)), ("trick", np.int64, (3, 4)),
                 ("down", bool, (4,)), ("ints", np.int64, (8,)), ("flags", bool, (7,)), ("won", np.int64, (4,)),
                 ("known", bool, (4,)), ("points_table", np.float64, (14, 4)))


def _layout(max_states, max_cands, max_branches=MAX_BRANCHES):
    """(name, dtype, shape, offset) of each array in a block, and its size."""
    arrays = (("states", np.uint8, (max_states, F.STATE_BYTES)), ("counts", np.int64, (max_states,)),
              ("cands", np.int16, (max_cands,)), ("q", np.float32, (max_cands,)), ("best", np.int64, (max_states,)),
              *(("b_" + name, dtype, (max_branches, *shape)) for name, dtype, shape in BRANCH_FIELDS),
              ("packed", np.uint8, (max_branches, 4, F.STATE_BYTES)), ("index", np.int64, (max_branches,)),
              ("points", np.float64, (max_branches, 4)))
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

    def branches(self, n):
        """The first n branches' tbranch arrays (views)."""
        return {name: getattr(self, "b_" + name)[:n] for name, _, _ in BRANCH_FIELDS}


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
        self.waited = [0.0, 0.0]  # seconds waited for the server: SCORE, ROLLOUT requests

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
        self._ask((self.spec.actor_id, SCORE, n, total))
        return b.q[:total].copy(), b.best[:n].copy()

    def rollouts(self, arrays, packed, index):
        """trollout.Rollouts.points_arrays on the server: runde points per
        seat, float64 [n, 4], of the branches (tbranch.branch_arrays and
        static_packed)."""
        n = len(index)
        if n > MAX_BRANCHES:
            parts = []
            for start in range(0, n, MAX_BRANCHES):
                rows, inverse = np.unique(index[start:start + MAX_BRANCHES], return_inverse=True)
                parts.append(self.rollouts({k: v[start:start + MAX_BRANCHES] for k, v in arrays.items()},
                                           packed[rows], inverse.astype(np.int64)))
            return np.concatenate(parts)
        b = self.buffers
        for name, value in arrays.items():
            getattr(b, "b_" + name)[:n] = value
        u = len(packed)
        b.packed[:u] = packed
        b.index[:n] = index
        self._ask((self.spec.actor_id, ROLLOUT, n, u))
        return b.points[:n].copy()

    def _ask(self, request):
        t0 = time.perf_counter()
        self.spec.requests.put(request)
        while not self.spec.done.acquire(timeout=0.5):
            if self.stop_event.is_set():
                raise Stopped()
        self.waited[request[1]] += time.perf_counter() - t0


def score_pending(model, actions, device, buffers, pending):
    """Scores the pending requests [(actor id, decisions, candidates)] of
    the actors' blocks in one forward pass and writes each its results."""
    from .net import score_arrays
    packed = np.concatenate([buffers[a].states[:n] for a, _, n, _ in pending])
    counts = np.concatenate([buffers[a].counts[:n] for a, _, n, _ in pending])
    flat = np.concatenate([buffers[a].cands[:c] for a, _, _, c in pending]).astype(np.int64)
    q, best = score_arrays(model, actions, device, packed, counts, flat)
    n0 = c0 = 0
    for a, _, n, c in pending:
        buffers[a].q[:c] = q[c0:c0 + c]
        buffers[a].best[:n] = best[n0:n0 + n]
        n0, c0 = n0 + n, c0 + c


def roll_pending(rollouts, buffers, pending):
    """Plays the pending rollout requests [(actor id, ROLLOUT, branches,
    statics)] of the actors' blocks in one trollout batch and writes each
    its points."""
    arrays = {name: np.concatenate([buffers[a].branches(n)[name] for a, _, n, _ in pending])
              for name, _, _ in BRANCH_FIELDS}
    packed = np.concatenate([buffers[a].packed[:u] for a, _, _, u in pending])
    index, u0 = [], 0
    for a, _, n, u in pending:
        index.append(buffers[a].index[:n] + u0)
        u0 += u
    points = rollouts.points_arrays(arrays, packed, np.concatenate(index))
    n0 = 0
    for a, _, n, _ in pending:
        buffers[a].points[:n] = points[n0:n0 + n]
        n0 += n


def _roll_worker(rollouts, buffers, dones, roll_queue, weights, device):
    """The server's rollout thread: a rollout batch takes a few hundred ms
    of GPU, and the actors' score requests must not wait behind it, so the
    rollouts play here, on their own CUDA stream, while the main thread
    scores. Waiting rollout requests of several actors go in one batch."""
    import torch
    stream = torch.cuda.Stream(device) if device.type == "cuda" else None
    while True:
        rolls = roll_queue.get()
        if rolls is None:
            return
        while True:
            try:
                more = roll_queue.get_nowait()
            except queue_module.Empty:
                break
            if more is None:
                roll_queue.put(None)
                break
            rolls += more
        with weights, torch.inference_mode():
            if stream is not None:
                with torch.cuda.stream(stream):
                    roll_pending(rollouts, buffers, rolls)
            else:
                roll_pending(rollouts, buffers, rolls)
        for a, _, _, _ in rolls:
            dones[a].release()


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
    rollouts = None
    if getattr(config, "search_gpu_rollouts", False):
        from .trollout import Rollouts
        rollouts = Rollouts(model, device)
        rollouts.capture_all()  # before the rollout thread runs beside this one
    blocks = [shared_memory.SharedMemory(name=name) for name, _, _ in specs]
    buffers = [Buffers(shm.buf, s, c) for shm, (_, s, c) in zip(blocks, specs)]
    weights = threading.Lock()  # a rollout batch and a change of weights do not overlap
    roll_queue = queue_module.Queue()
    worker = None
    if rollouts is not None:
        worker = threading.Thread(target=_roll_worker, daemon=True,
                                  args=(rollouts, buffers, dones, roll_queue, weights, device))
        worker.start()
    seen = -1
    try:
        while not stop_event.is_set():
            if version.value != seen:
                with lock, weights:
                    seen = version.value
                    model.load_state_dict(shared_model.state_dict())
                    if rollouts is not None:
                        rollouts.refresh()
            try:
                pending = [requests.get(timeout=0.2)]
            except queue_module.Empty:
                continue
            while len(pending) < len(buffers):
                try:
                    pending.append(requests.get_nowait())
                except queue_module.Empty:
                    break
            rolls = [p for p in pending if p[1] == ROLLOUT]
            if rolls:
                roll_queue.put(rolls)  # the rollout thread answers them
            scores = [p for p in pending if p[1] == SCORE]
            if scores:
                score_pending(model, actions, device, buffers, scores)
                for a, _, _, _ in scores:
                    dones[a].release()
            if stats is not None:
                stats["passes"] = stats.get("passes", 0) + 1
                stats["requests"] = stats.get("requests", 0) + len(pending)
    finally:
        if worker is not None:
            roll_queue.put(None)
            worker.join(timeout=10)
        del buffers
        for shm in blocks:
            try:
                shm.close()
            except BufferError:  # a view still alive; the process ends anyway
                pass
