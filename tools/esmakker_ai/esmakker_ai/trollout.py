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

import numpy as np
import torch

from . import features as F
from . import tengine as T
from . import tfeatures as TF

PAIR_CHUNK = 1 << 16  # (branch, candidate) pairs per Q pass: bounds the GPU memory


def slot_action_bits(device):
    """float32 [SLOTS, ACTION_BITS]: the net's action input of each slot."""
    packed = np.frombuffer(b"".join(F.action_bytes(a) for a in T.SLOT_ACTION), np.uint8)
    bits = np.unpackbits(packed.reshape(T.SLOTS, F.ACTION_BYTES), axis=-1, bitorder="little")
    return torch.from_numpy(bits.astype(np.float32)).to(device)


def choose(model, st, static, rows, action_embed, trace=None):
    """Each row's decision now, the net greedy: (seat, slot, offer)."""
    seat, mask, offer = T.decision(st, rows)
    h = model.encode_state(TF.encode(st, static, rows, seat).float())
    pair_row, pair_slot = mask.nonzero(as_tuple=True)
    q = torch.empty(pair_row.shape[0], device=st.device)
    for start in range(0, pair_row.shape[0], PAIR_CHUNK):
        r, s = pair_row[start:start + PAIR_CHUNK], pair_slot[start:start + PAIR_CHUNK]
        q[start:start + PAIR_CHUNK] = model.q(torch.cat([h[r], action_embed[s]], dim=1)).squeeze(1)
    values = torch.full(mask.shape, float("-inf"), device=st.device)
    values[pair_row, pair_slot] = q
    best = values.max(1, keepdim=True).values
    order = T.tie_order(st, rows).masked_fill_(~(mask & (values == best)), 1 << 20)
    slot = order.argmin(1)
    if trace is not None:
        trace.append((rows.cpu(), slot.cpu(), values.cpu(), offer.cpu()))
    return seat, slot, offer


def rollout(model, st, static, trace=None):
    """Plays every branch of `st` (in place) to the end of its runde, the
    net greedy at every seat; `static` is tfeatures.static_rows of its
    Rounds. Returns the runde points per seat, float64 [B, 4] on the device.
    `trace` (a list): each step's (rows, slots, Q per slot, offer) is
    appended (on the CPU)."""
    with torch.inference_mode():
        action_embed = model.action(slot_action_bits(st.device))
        while True:
            rows = (~st.done).nonzero().squeeze(1)
            if not rows.numel():
                break
            seat, slot, offer = choose(model, st, static, rows, action_embed, trace)
            T.apply(st, rows, seat, slot, offer)
        return T.points(st)


def rollout_rounds(model, rounds, spils, device, offered=None, trace=None):
    """rollout() of Rounds (not changed): points per seat, numpy float64
    [B, 4]. spils: a SpilContext or None per Round; offered: per Round,
    whether the melder was asked about fordækt out of turn already."""
    st = T.from_rounds(rounds, device, offered)
    static = TF.static_rows(rounds, spils, device)
    return rollout(model, st, static, trace).cpu().numpy()
