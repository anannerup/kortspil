"""Search rollouts of stik runder on the GPU: many branches (Rounds in the
PLAYING phase of a stik melding) played to the end of the runde at once,
the net greedy at every seat, all in tensors (tengine.py, tfeatures.py).

It plays what search.py's rollouts play with the net at all four seats
(agent.play_steps with NetPlayer(model, 0.0) everywhere): at each step every
unfinished branch takes its one decision (the fordækt offer out of turn,
or the seat to act's card or fordækt), scored by the net in one forward
pass for all branches, the best candidate taken (the first of the highest
Q, as np.argmax over the CPU candidates' order). tests/test_trollout.py
compares the choices and the points with the CPU path.

A branch with Svær (or any bot) at a seat, a sol-melding, or a runde not
yet in its card play stays on the CPU.
"""

from dataclasses import fields

import numpy as np
import torch

from . import features as F
from . import tengine as T
from . import tfeatures as TF

MAX_CANDIDATES = 26  # the melder's first lead: 13 cards to play, 13 to lay fordækt
ROW_CHUNK = 2048  # rows per Q pass: bounds the GPU memory ([rows, 26, 256] floats)


def slot_action_bits(device):
    """float32 [SLOTS, ACTION_BITS]: the net's action input of each slot."""
    packed = np.frombuffer(b"".join(F.action_bytes(a) for a in T.SLOT_ACTION), np.uint8)
    bits = np.unpackbits(packed.reshape(T.SLOTS, F.ACTION_BYTES), axis=-1, bitorder="little")
    return torch.from_numpy(bits.astype(np.float32)).to(device)


class QHead:
    """The net's Q of every slot, split at its first layer: Linear(cat(h, a))
    = W_h h + (W_a a + b), the action part made once for the SLOTS slots.
    The same Q as net.q_values up to float rounding (the sum's order)."""

    def __init__(self, model, device):
        first, self.relu, self.last = model.q[0], model.q[1], model.q[2]
        hidden = first.in_features - model.action[0].out_features
        self.w_state = first.weight[:, :hidden]
        embed = model.action(slot_action_bits(device))
        self.slot_part = embed @ first.weight[:, hidden:].T + first.bias  # [SLOTS, 256]

    def __call__(self, h, slots):
        """Q [n, k] of candidate slots [n, k] for states h [n, hidden]."""
        out = torch.empty(slots.shape, device=h.device)
        for start in range(0, h.shape[0], ROW_CHUNK):
            part = h[start:start + ROW_CHUNK] @ self.w_state.T
            z = self.relu(part[:, None, :] + self.slot_part[slots[start:start + ROW_CHUNK]])
            out[start:start + ROW_CHUNK] = self.last(z).squeeze(2)
        return out


def choose(model, st, static, rows, head, trace=None):
    """Each row's decision now, the net greedy: (seat, slot, offer). The
    candidates are each row's first MAX_CANDIDATES slots of its mask; a row
    without any (finished) gets slot 0, which changes nothing. No host sync."""
    seat, mask, offer = T.decision(st, rows)
    h = model.encode_state(TF.encode(st, static, rows, seat).float())
    rank = mask * (T.SLOTS - torch.arange(T.SLOTS, device=st.device))  # lower slots first
    key, slots = rank.topk(MAX_CANDIDATES, dim=1)
    valid = key > 0
    q = head(h, slots).masked_fill_(~valid, float("-inf"))
    best = q.max(1, keepdim=True).values
    order = T.tie_order(st, rows).gather(1, slots).masked_fill_(~(valid & (q == best)), 1 << 20)
    slot = torch.where(valid.any(1), slots.gather(1, order.argmin(1, keepdim=True)).squeeze(1),
                       torch.zeros_like(seat))
    if trace is not None:
        values = torch.full(mask.shape, float("-inf"), device=st.device).scatter_(1, slots, q)
        trace.append((rows.cpu(), slot.cpu(), values.cpu(), offer.cpu()))
    return seat, slot, offer


def decisions_left(st):
    """The most decisions any row still takes: its cards to play, and the
    fordækt offer and laying fordækt before the first lead."""
    return int((4 * (T.STIK_COUNT - st.n_tricks) - st.trick_len).max()) + 2 if st.size else 0


def rollout(model, st, static, trace=None, check_every=4):
    """Plays every branch of `st` (in place) to the end of its runde, the
    net greedy at every seat; `static` is tfeatures.static_rows of its
    Rounds. Returns the runde points per seat, float64 [B, 4] on the device.
    `trace` (a list): each step's (rows, slots, Q per slot, offer) is
    appended (on the CPU).

    Every row takes a step each time, a finished one the no-op slot 0 (it
    has no candidates), so the steps need no host sync but the Q pass's;
    whether all are done is asked every `check_every` steps."""
    with torch.inference_mode():
        head = QHead(model, st.device)
        rows = torch.arange(st.size, device=st.device)
        for step in range(decisions_left(st)):
            if step % check_every == 0 and bool(st.done.all()):
                break
            seat, slot, offer = choose(model, st, static, rows, head, trace)
            T.apply(st, rows, seat, slot, offer)
        return T.points(st)


def rollout_rounds(model, rounds, spils, device, offered=None, trace=None):
    """rollout() of Rounds (not changed): points per seat, numpy float64
    [B, 4]. spils: a SpilContext or None per Round; offered: per Round,
    whether the melder was asked about fordækt out of turn already."""
    st = T.from_rounds(rounds, device, offered)
    static = TF.static_rows(rounds, spils, device)
    return rollout(model, st, static, trace).cpu().numpy()


def _blank(size, device):
    """A TState of `size` finished rows that take no decision (padding)."""
    def long(*shape, v=0):
        return torch.full(shape, v, dtype=torch.long, device=device)

    def flag(*shape, v=False):
        return torch.full(shape, v, dtype=torch.bool, device=device)

    return T.TState(
        hands=flag(size, 4, 55), played=flag(size, 4, 55), void=flag(size, 4, 4), tricks_won=long(size, 4),
        trick_card=long(size, 4, v=-1), trick_suit=long(size, 4, v=-1), trick_rank=long(size, 4, v=-1),
        trick_down=flag(size, 4), trick_len=long(size), n_tricks=long(size, v=T.STIK_COUNT), leader=long(size),
        trump=long(size), called=long(size), melder=long(size), esmakker=long(size, v=-1),
        fordaekt=long(size, v=-1), fd_played=flag(size), fd_done=flag(size), ace_played=flag(size),
        called_led=flag(size), fd_ok=flag(size), known=flag(size, 4), joker_trumpable=flag(size),
        offered=flag(size, v=True),
        points_table=torch.zeros(size, T.STIK_COUNT + 1, 4, dtype=torch.float64, device=device),
        done=flag(size, v=True))


class GraphRollout:
    """rollout() with each step captured once as a CUDA graph and replayed:
    one launch per step instead of some hundreds of small kernels, which is
    what a step costs otherwise (launch overhead, not compute). The graph
    plays `size` rows; a smaller batch is padded with finished rows. The
    same kernels as rollout(), so the same results. The graph holds its own
    GPU memory: free() it when done."""

    def __init__(self, model, size, device, check_every=4):
        self.model, self.size, self.device, self.check_every = model, size, device, check_every
        self.st = _blank(size, device)
        self.static = torch.zeros(size, 4, F.STATE_BITS, dtype=torch.bool, device=device)
        self.rows = torch.arange(size, device=device)
        with torch.no_grad():
            self.head = QHead(model, device)
            stream = torch.cuda.Stream(device)
            stream.wait_stream(torch.cuda.current_stream(device))
            with torch.cuda.stream(stream):
                for _ in range(2):  # warm-up on blank rows (changes nothing)
                    self._step()
            torch.cuda.current_stream(device).wait_stream(stream)
            self.graph = torch.cuda.CUDAGraph()
            with torch.cuda.graph(self.graph):
                self._step()

    def _step(self):
        seat, slot, offer = choose(self.model, self.st, self.static, self.rows, self.head)
        T.apply(self.st, self.rows, seat, slot, offer)

    def run(self, st, static):
        """Plays the branches of `st` (not changed) to the end: points per
        seat, float64 [B, 4] on the device."""
        n = st.size
        if n > self.size:
            raise ValueError(f"{n} branches, the graph plays {self.size}")
        blank = _blank(self.size - n, self.device) if n < self.size else None
        for f in fields(T.TState):
            dst = getattr(self.st, f.name)
            dst[:n].copy_(getattr(st, f.name))
            if blank is not None:
                dst[n:].copy_(getattr(blank, f.name))
        self.static[:n].copy_(static)
        for step in range(decisions_left(st)):
            if step % self.check_every == 0 and bool(self.st.done.all()):
                break
            self.graph.replay()
        return T.points(self.st)[:n].clone()

    def free(self):
        del self.graph, self.st, self.static, self.head
        torch.cuda.empty_cache()


class Rollouts:
    """What search would call: Rounds in, runde points out, played on the
    GPU by CUDA graphs of a few fixed sizes (powers of two from `smallest`
    to `largest`; a batch is padded up to the next, a bigger one split).
    The graphs are captured on first use and kept: free() them. On a CPU
    device it plays eagerly (rollout())."""

    def __init__(self, model, device, smallest=256, largest=4096):
        self.model, self.device = model, torch.device(device)
        self.smallest, self.largest = smallest, largest
        self.graphs = {}

    def _graph(self, n):
        size = self.smallest
        while size < n:
            size *= 2
        if size not in self.graphs:
            self.graphs[size] = GraphRollout(self.model, size, self.device)
        return self.graphs[size]

    def points(self, rounds, spils, offered=None):
        """Runde points per seat, numpy float64 [len(rounds), 4], of each
        Round (in the PLAYING phase of a stik melding; not changed) played
        out greedy by the net at every seat. spils: a SpilContext or None per
        Round; offered: whether its melder was asked about fordækt out of
        turn already (default no)."""
        out = []
        for start in range(0, len(rounds), self.largest):
            part = rounds[start:start + self.largest]
            off = offered[start:start + self.largest] if offered is not None else None
            st = T.from_rounds(part, self.device, off)
            static = TF.static_rows(part, spils[start:start + self.largest], self.device)
            if self.device.type == "cuda":
                out.append(self._graph(len(part)).run(st, static).cpu().numpy())
            else:
                out.append(rollout(self.model, st, static).cpu().numpy())
        return np.concatenate(out) if out else np.zeros((0, 4))

    def free(self):
        for graph in self.graphs.values():
            graph.free()
        self.graphs = {}
