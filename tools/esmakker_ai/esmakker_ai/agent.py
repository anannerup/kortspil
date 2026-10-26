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
from .selfplay import ask_fordaekt, fordaekt_offer

RUNDE_TARGETS = 6  # points, own stik, makker's stik, ace holder class, own-stik mask, makker-stik mask
TARGETS = RUNDE_TARGETS + 2  # ... then the Q target (points and the spil's part), the spil's win share
Q_TARGET, WIN_TARGET = RUNDE_TARGETS, RUNDE_TARGETS + 1
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

    def decide(self, r, seat, chosen=(), spil=None):
        """(action id, or None when the net must score the candidates; the
        state's bytes; the candidates; whether it was a choice at all).
        `spil`: the runde's SpilContext (None: the first runde of a spil)."""
        cands = F.candidates(r, seat, chosen)
        state = F.to_bytes(F.encode(r, seat, C.mask(chosen), spil))
        if len(cands) == 1:
            return cands[0], state, cands, False
        bidding = r.phase == BIDDING
        epsilon = self.bid_epsilon if bidding else self.epsilon
        if epsilon and self.rng.random() < epsilon:
            return self.rng.choice(explore_bids(cands) if bidding else cands), state, cands, True
        return None, state, cands, True

    def choose(self, r, seat, chosen=(), spil=None):
        """(action id, the state's bytes, whether it was a choice at all)."""
        action, state, cands, choice = self.decide(r, seat, chosen, spil)
        if action is None:
            action = cands[int(np.argmax(self.scores(state, cands)))]
        return action, state, choice


def net_choice(player, r, seat, chosen=(), spil=None, where=None):
    """A NetPlayer's choice inside play_steps: yields (player, state bytes,
    candidates, where) when the net must score them, and is sent the action.
    `where`, for search.py: (round, seat, kind, players, bidders, spil), kind
    "act" (an engine action), "discard" (one card of a discard, or the stop)
    or "offer" (fordækt out of turn)."""
    action, state, cands, choice = player.decide(r, seat, chosen, spil)
    if action is None:
        action = yield player, state, cands, where
    return action, state, choice


def explore_bids(cands, lowest=3):
    """What a random bid explores: pas and the other non-bids, and only the
    lowest few meldinger (a random 13 vip teaches little but noise)."""
    bids = [a for a in cands if a < A.PAS]  # legal_actions lists them lowest first
    return [a for a in cands if a >= A.PAS] + bids[:lowest]


def play(r, players, record=(), stats=None, bidders=None, spil=None):
    """Plays the runde to its end in place. players: one per seat, a
    NetPlayer or a bot acting on observations (bots.py). Returns, per seat
    in `record`, the net's choices [(state bytes, action id)] (forced moves
    left out).

    A discard is chosen card by card until DISCARD_STOP or the most the
    seat may lay away (features.py). Before the forhånd leads the first
    stik, a melder who is not the forhånd is asked once whether she lays
    fordækt out of turn (NO_FORDAEKT or a fordækt card; a bot through
    selfplay.ask_fordaekt), as the engine allows. `stats`, a dict, counts
    the net's exchanges: stats["exchanged"][n] at a stik melding,
    stats["sol_exchanged"][n] at a sol-melding. `spil`: the runde's
    SpilContext (spil.py; None: the first runde of a spil)."""
    steps = play_steps(r, players, record, stats, bidders, spil)
    try:
        request = next(steps)
        while True:
            player, state, cands = request[:3]
            request = steps.send(cands[int(np.argmax(player.scores(state, cands)))])
    except StopIteration as done:
        return done.value


def play_steps(r, players, record=(), stats=None, bidders=None, spil=None, offered=False):
    """play() as a generator: it yields (player, state bytes, candidates)
    at each net decision that needs scoring and is sent the chosen action,
    so an actor can score the decisions of many runder in one batch (on the
    GPU). Returns what play() returns. With `bidders` (bots, one per seat)
    the meldingsrunde is theirs and gives no samples; the net plays from the
    declaration on (a curriculum: self-play alone settles on one melding).
    `offered`: the melder was asked about fordækt out of turn already (a
    search rollout that starts right after that question)."""
    decisions = {seat: [] for seat in record}
    while not r.over():
        if r.phase == BANKING:
            r.apply(r.melder, A.BANKSLUT, check=False)
            continue
        if not offered and fordaekt_offer(r) is not None:
            offered = True
            seat = r.melder
            player = players[seat]
            if isinstance(player, NetPlayer):
                action, state, choice = yield from net_choice(player, r, seat, spil=spil,
                                                              where=(r, seat, "offer", players, bidders, spil))
                if choice and seat in decisions:
                    decisions[seat].append((state, action))
                if action == F.NO_FORDAEKT:
                    action = None
            else:
                action = ask_fordaekt(player, observe(r, seat))
            if action is not None:
                r.apply(seat, action, check=False)
            continue
        seat = r.to_act()
        player = bidders[seat] if bidders is not None and r.phase == BIDDING else players[seat]
        if not isinstance(player, NetPlayer):
            r.apply(seat, player.act(observe(r, seat)), check=False)
            continue
        size = r.discard_size(seat)
        if size:
            chosen = []
            while len(chosen) < size:
                action, state, choice = yield from net_choice(player, r, seat, chosen, spil,
                                                              (r, seat, "discard", players, bidders, spil))
                if choice and seat in decisions:
                    decisions[seat].append((state, action))
                if action == F.DISCARD_STOP:
                    break
                chosen.append(action - F.DISCARD)
            if stats is not None:
                key = "sol_exchanged" if r.kind == "sol" else "exchanged"
                counts = stats.setdefault(key, [0, 0, 0, 0])
                counts[len(chosen)] += 1
            r.apply(seat, tuple(chosen), check=False)
        else:
            action, state, choice = yield from net_choice(player, r, seat, spil=spil,
                                                          where=(r, seat, "act", players, bidders, spil))
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
    """The runde's targets for the seat (RUNDE_TARGETS of them); the spil's
    two follow in spil_targets."""
    complete = r.complete()
    if not complete:  # a redeal: 0 points, no stik
        return (0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
    makker = makker_of(r, seat)
    makker_stik = 0 if makker in (None, -1) else r.tricks_won[makker]
    return (float(r.points()[seat]), float(r.tricks_won[seat]), float(makker_stik),
            float(ace_holder_class(r, seat)), 1.0, 0.0 if makker is None else 1.0)


def spil_targets(points, before, after, seat, config):
    """The Q target and the win share for a seat's samples of one runde.

    Q = the runde's points + spil_weight × (the change the runde made in the
    seat's expected spil outcome), where the spil outcome is the final margin
    (own total − the best other total: a big win is worth more than a narrow
    one, a narrow loss less bad than a big one) + win_value × the win share
    (1, 1/n in a tie, 0). `before` and `after` are spil.expected_outcome()
    before and after the runde (spil_target "expected"); with spil_target
    "outcome", `after` is the spil's actual end. Summed over a spil's runder
    the "expected" changes add up to the actual outcome less the expected
    outcome at the start, which is the same for every seat."""
    (m0, w0), (m1, w1) = before, after
    part = (m1[seat] - m0[seat]) + config.win_value * (w1[seat] - w0[seat])
    return points + config.spil_weight * part


def explain(model, r, seat, chosen=(), spil=None):
    """What the net thinks at the seat's decision (for "Vis kort"): the
    value of each candidate action (Q: the runde's points and the spil's
    part, in points), the expected runde points, own and makker's stik, who
    it guesses holds the called ace, and its chance to win the spil."""
    cands = F.candidates(r, seat, chosen)
    state = F.to_bytes(F.encode(r, seat, C.mask(chosen), spil))
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
        "win": float(torch.sigmoid(heads["win"][0])),
    }
