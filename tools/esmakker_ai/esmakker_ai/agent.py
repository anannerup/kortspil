"""The net as a player, a runde played with it, and the training targets.

The net only ever sees features.encode(r, seat): the features are the
visibility gate (tests/test_features.py). Bots never bank (strategy §2): in
the bank window nobody banks and the melder closes it.
"""

import numpy as np
import torch

from . import actions as A
from . import cards as C
from . import features as F
from .engine import BANKING, BIDDING
from .net import MAKKER_CLASSES, unpack
from .observation import observe

TARGETS = 6  # points, own stik, makker's stik, ace holder class, own-stik mask, makker-stik mask
ACTION_TABLE = unpack(np.frombuffer(b"".join(F.action_bytes(a) for a in range(F.ACTION_KINDS)), np.uint8)
                      .reshape(F.ACTION_KINDS, F.ACTION_BYTES))


class NetPlayer:
    """Chooses with the net (CPU, one decision at a time); epsilon of the
    choices are random, bid_epsilon of those in the meldingsrunde
    (exploration in self-play; 0 for evaluation)."""

    def __init__(self, model, epsilon=0.0, rng=None, bid_epsilon=None):
        self.model = model
        self.epsilon = epsilon
        self.bid_epsilon = epsilon if bid_epsilon is None else bid_epsilon
        self.rng = rng

    def scores(self, state_bytes, cands):
        s = torch.from_numpy(unpack(np.frombuffer(state_bytes, np.uint8))[None])
        a = torch.from_numpy(ACTION_TABLE[cands])
        with torch.inference_mode():
            h = self.model.encode_state(s)
            return self.model.q_values(h.expand(len(cands), -1), a).numpy()

    def choose(self, r, seat, chosen=()):
        """(action id, the state's bytes, whether it was a choice at all)."""
        cands = F.candidates(r, seat, chosen)
        state = F.to_bytes(F.encode(r, seat, C.mask(chosen)))
        if len(cands) == 1:
            return cands[0], state, False
        bidding = r.phase == BIDDING
        epsilon = self.bid_epsilon if bidding else self.epsilon
        if epsilon and self.rng.random() < epsilon:
            return self.rng.choice(explore_bids(cands) if bidding else cands), state, True
        return cands[int(np.argmax(self.scores(state, cands)))], state, True


def explore_bids(cands, lowest=3):
    """What a random bid explores: pas and the other non-bids, and only the
    lowest few meldinger (a random 13 vip teaches little but noise)."""
    bids = [a for a in cands if a < A.PAS]  # legal_actions lists them lowest first
    return [a for a in cands if a >= A.PAS] + bids[:lowest]


def play(r, players, record=()):
    """Plays the runde to its end in place. players: one per seat, a
    NetPlayer or a bot acting on observations (bots.py). Returns, per seat
    in `record`, the net's choices [(state bytes, action id)] (forced moves
    left out)."""
    decisions = {seat: [] for seat in record}
    while not r.over():
        if r.phase == BANKING:
            r.apply(r.melder, A.BANKSLUT, check=False)
            continue
        seat = r.to_act()
        player = players[seat]
        if not isinstance(player, NetPlayer):
            r.apply(seat, player.act(observe(r, seat)), check=False)
            continue
        size = r.discard_size(seat)
        if size:
            chosen = []
            for _ in range(size):
                action, state, choice = player.choose(r, seat, chosen)
                if choice and seat in decisions:
                    decisions[seat].append((state, action))
                chosen.append(action - F.DISCARD)
            r.apply(seat, tuple(chosen), check=False)
        else:
            action, state, choice = player.choose(r, seat)
            if choice and seat in decisions:
                decisions[seat].append((state, action))
            r.apply(seat, action, check=False)
    return decisions


def makker_of(r, seat):
    """The seat's makker at the end of a stik melding, None when it has
    none to speak of (sol, or an opponent of a selvmakker); -1 for a
    selvmakker herself (no makker: 0 stik)."""
    if r.kind != "stik":
        return None
    if seat == r.melder:
        return -1 if r.esmakker is None else r.esmakker
    if seat == r.esmakker:
        return r.melder
    if r.esmakker is None:
        return None
    return next(s for s in range(4) if s not in (seat, r.melder, r.esmakker))


def ace_holder_class(r, seat):
    """Who held the called ace, relative to the seat (0-3), or 4: the kitty."""
    if r.called_ace is None:
        return 0
    bit = 1 << C.ace(r.called_ace)
    for s in range(4):
        if r.deal_hands[s] & bit:
            return (s - seat) % 4
    return 4


def targets(r, seat):
    complete = r.complete()
    if not complete:  # a redeal: 0 points, no stik
        return (0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
    makker = makker_of(r, seat)
    makker_stik = 0 if makker in (None, -1) else r.tricks_won[makker]
    return (float(r.points()[seat]), float(r.tricks_won[seat]), float(makker_stik),
            float(ace_holder_class(r, seat)), 1.0, 0.0 if makker is None else 1.0)


def explain(model, r, seat, chosen=()):
    """What the net thinks at the seat's decision (for "Vis kort"): points
    per candidate action, the expected runde points, own and makker's stik,
    and who it guesses holds the called ace."""
    cands = F.candidates(r, seat, chosen)
    state = F.to_bytes(F.encode(r, seat, C.mask(chosen)))
    s = torch.from_numpy(unpack(np.frombuffer(state, np.uint8))[None])
    with torch.inference_mode():
        h = model.encode_state(s)
        heads = model.heads(h)
        q = model.q_values(h.expand(len(cands), -1), torch.from_numpy(ACTION_TABLE[cands])) if cands else None
    scale = float(model.points_scale)
    probs = torch.softmax(heads["makker"][0], 0).tolist()
    guess = {(seat + k) % 4: probs[k] for k in range(4)}
    guess["kitty"] = probs[MAKKER_CLASSES - 1]
    return {
        "actions": {a: float(v) * scale for a, v in zip(cands, q.tolist() if q is not None else [])},
        "points": float(heads["value"][0]) * scale,
        "own_stik": float(heads["stik"][0, 0]),
        "makker_stik": float(heads["stik"][0, 1]),
        "ace_holder": guess,
    }
