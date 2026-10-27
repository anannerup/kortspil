"""The net as a player, a runde played with it, and the training targets.

The net only ever sees features.encode(r, seat): the features are the
visibility gate (tests/test_features.py). Bots never bank (strategy §2): in
the bank window nobody banks and the melder closes it.
"""

import numpy as np

from . import actions as A
from . import cards as C
from . import features as F
from . import meldinger as M
from .engine import BANKING, BIDDING
from .observation import observe
from .selfplay import ask_fordaekt, fordaekt_offer

RUNDE_TARGETS = 6  # points, own stik, makker's stik, ace holder class, own-stik mask, makker-stik mask
# ... then the Q target (points and the spil's part), the spil's win share, and the contract
# head's label: the trump (0-4; -1 none: the seat was not the melder of a played stik melding)
# and the side's stik (net.py)
TARGETS = RUNDE_TARGETS + 4
Q_TARGET, WIN_TARGET, CONTRACT_TRUMP, CONTRACT_SIDE = RUNDE_TARGETS, RUNDE_TARGETS + 1, RUNDE_TARGETS + 2, RUNDE_TARGETS + 3
NO_CONTRACT = (-1.0, 0.0)
# every action's bits as float32 0/1 rows (net.unpack; numpy here: the actors import no torch)
ACTION_TABLE = np.unpackbits(np.frombuffer(b"".join(F.action_bytes(a) for a in range(F.ACTION_KINDS)), np.uint8)
                             .reshape(F.ACTION_KINDS, F.ACTION_BYTES), axis=-1, bitorder="little").astype(np.float32)


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
        import torch
        from .net import score_one, unpack
        s = torch.from_numpy(unpack(np.frombuffer(state_bytes, np.uint8))[None])
        return score_one(self.model, s, cands)[0].numpy()

    def decide(self, r, seat, chosen=(), spil=None):
        """(action id, or None when the net must score the candidates; the
        state's bytes; the candidates; whether it was a choice at all).
        `spil`: the runde's SpilContext (None: the first runde of a spil)."""
        cands = net_candidates(self.model, r, seat, chosen)
        state = F.to_bytes(F.encode(r, seat, C.mask(chosen), spil))
        if len(cands) == 1:
            return cands[0], state, cands, False
        bidding = r.phase == BIDDING
        epsilon = self.bid_epsilon if bidding else self.epsilon
        if epsilon and self.rng.random() < epsilon:
            return self.rng.choice(explore_bids(cands, rng=self.rng) if bidding else cands), state, cands, True
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


EXPLORE_SOL = 0.2  # share of random bids that may also be a sol-melding


def net_candidates(model, r, seat, chosen=()):
    """The candidates the net chooses among: F.candidates, without the
    sol-meldinger and going along on a sol when the net is a stik net
    (model.no_sol; Anders: "make it verboten at melde det")."""
    cands = F.candidates(r, seat, chosen)
    if not getattr(model, "no_sol", False) or r.phase != BIDDING:
        return cands
    sol = r.melding is not None and M.is_sol(r.melding)
    kept = [a for a in cands if not (a < A.PAS and M.is_sol(a - A.BID)) and not (a == A.MED and sol)]
    return kept or cands


def explore_bids(cands, lowest=3, rng=None, sol=EXPLORE_SOL, up_to=None):
    """What a random bid explores: pas and the other non-bids, the lowest
    few stik meldinger (a random 13 vip teaches little but noise), with
    `up_to` also the plain melding of every number up to it, and the
    sol-meldinger only a `sol` share of the time (rng; never without one):
    sol sits just above 9, and self-play that always tries it drowns in sol
    that goes bet (Anders: "tag sol med nogle gange")."""
    def is_stik(a):
        return a < A.PAS and not M.is_sol(a - A.BID)

    stik = [a for a in cands if is_stik(a)]  # legal_actions lists them lowest first
    out = [a for a in cands if a >= A.PAS] + stik[:lowest]
    if up_to:
        out += [a for a in stik[lowest:] if M.pahaeng(a - A.BID) == M.NONE and M.number(a - A.BID) <= up_to]
    if rng is not None and rng.random() < sol:
        out += [a for a in cands if a < A.PAS and M.is_sol(a - A.BID)]
    return out


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
            r.apply(seat, bot_act(player, r, seat), check=False)
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


def __getattr__(name):
    """agent.SimulatingPlayer: the bot that melder by simulation (it lives in
    search.py, which imports this module; the ladder looks for it here)."""
    if name == "SimulatingPlayer":
        from .search import SimulatingPlayer
        return SimulatingPlayer
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")


def bot_act(bot, r, seat):
    """bot.act(observe(r, seat)); a bot with act_round (Svær) reads the
    Round itself, the same as from the observation but without building it."""
    act_round = getattr(bot, "act_round", None)
    if act_round is not None:
        return act_round(r, seat)
    return bot.act(observe(r, seat))


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


def side_stik(r):
    """The stik the melder's side took (melder and esmakker, or the
    selvmakker alone)."""
    return sum(r.tricks_won[s] for s in r.side())


def contract_label(r, seat):
    """The contract head's label for the seat's samples of a runde: (trump,
    the side's stik) when the seat was the melder of a played stik melding,
    else NO_CONTRACT. The learner uses it only on the seat's states before
    the card play (learner.contract_mask): "hvad den tror på af stik er
    ligegyldigt hvis ikke den bliver melder" (Anders)."""
    if not r.complete() or r.kind != "stik" or seat != r.melder:
        return NO_CONTRACT
    return float(r.trump), float(side_stik(r))


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
    import torch
    from .net import MAKKER_CLASSES, contract_bid_values, contract_expected_stik, score_one, unpack
    cands = net_candidates(model, r, seat, chosen)
    state = F.to_bytes(F.encode(r, seat, C.mask(chosen), spil))
    s = torch.from_numpy(unpack(np.frombuffer(state, np.uint8))[None])
    if cands:
        q, h = score_one(model, s, cands)
    else:
        q = None
        with torch.inference_mode():
            h = model.encode_state(s)
    with torch.inference_mode():
        heads = model.heads(h)
    scale = float(model.points_scale)
    probs = torch.softmax(heads["makker"][0], 0).tolist()
    guess = {(seat + k) % 4: probs[k] for k in range(4)}
    guess["kitty"] = probs[MAKKER_CLASSES - 1]
    contract = {}
    if "contract" in heads:
        # if this seat becomes melder: the side's expected stik per trump (0-3 the suits, 4 trumfløs)
        # and each stik melding's value to it (the best trump), in points
        with torch.inference_mode():
            stik = contract_expected_stik(heads["contract"])[0].tolist()
            values = contract_bid_values(heads["contract"])[0].tolist()
            dist = torch.softmax(heads["contract"][0].float(), dim=1).tolist()
        contract = {"contract_stik": dict(enumerate(stik)),
                    "contract_dist": dict(enumerate(dist)),  # per trump: the chance of each of the side's 0-13 stik
                    "contract_values": {M.CODES[m]: v for m, v in enumerate(values)}}
    return {
        "actions": {a: float(v) * scale for a, v in zip(cands, q.tolist() if q is not None else [])},
        "points": float(heads["value"][0]) * scale,
        "own_stik": float(heads["stik"][0, 0]),
        "makker_stik": float(heads["stik"][0, 1]),
        "ace_holder": guess,
        "win": float(torch.sigmoid(heads["win"][0])),
        **contract,
    }
