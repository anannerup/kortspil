"""Search in self-play: rollout targets (expert iteration, determinized
search). Anders: "lad den prøve flere forskellige træk fra en kandidatliste
og så over tid danne heuristikker over hvad der virker bedst i en given
situation."

At a share of the net's decisions (config search_share; search_share_bid
in the meldingsrunde, the declaration and fordækt out of turn) the actor
does not just play the net's best action. It takes the net's top
search_k candidates by Q, plus search_random others at random. In the
meldingsrunde it draws instead search_gumbel_k candidates from all legal
actions with chance softmax(Q / search_gumbel_tau), Gumbel AlphaZero style,
plus the net's own choice, and at the other decisions search_gumbel_k_play (the older search_bid_lowest, search_bid_up_to
and search_bid_sol lists add pas, the lowest stik meldinger, the plain ones
up to a number and sometimes sol). It samples search_worlds worlds the
deciding seat cannot tell from the real one (sample_world), and in each
world plays every candidate and then the rest of the runde out: the net
greedy on the net's seats, the partner bot (Svær) where the real game has
it. Each candidate's average runde points over the worlds (the same worlds for every candidate) becomes a Q target for that
(state, action), for all candidates, not only the one played; the learner
weighs these rows by search_weight and trains only the Q head on them
(learner.py). The actor then plays the candidate with the best average
(a random searched one with probability search_explore). The decision's
ordinary Monte Carlo row (the real runde's points for the action played)
is kept as well.

Never peeking: a world is built from the seat's observation alone
(observation.py) and accepted only when replaying the runde's actions in it
is legal and gives the seat exactly the same observation; in the rollouts
every seat decides from its own view of the sampled world (features.encode
or observe), as in a real runde. Only the hidden cards differ from the
truth, and they are drawn without looking at it.

Discards (chosen one card at a time) are not searched; everything else
the net chooses is.

With the contract head (config contract, net.py) a searched trump choice
also teaches it: every rollout gives a row (the state, the trump tried, the
stik the melder's side took with it) that only the contract head learns
from, so it sees what each trump would have brought, not only the one
chosen. With search_bid_pas a searched bid always tries pas as well: the
branch where another seat wins the melding and chooses trump, what the bids
are weighed against.

With contract_cf the contract head also gets counterfactual rows, at every
seat's first bid of a net-only runde, searched or not: in a world drawn as
above the seat bids the lowest plain stik melding and the others pass, so
it is melder; then for each trump it plays the declaration and the card
play out with the net, and the side's stik is a row for that trump at the
state the seat bid from. Every seat gets them, the weak hands too, not only
the one that won the melding on a guess that may have been too high (the
labels of the real melders alone are few and picked for optimism).

With bid_by_simulation the net never bids on its own (Anders: "måske skal
nettet slet ikke melde selv, måske skal det altid simulere"): every bid is
searched over pas and the meldinger of the next bid_sim_numbers numbers
(bid_options), in bid_sim_worlds worlds, and the best mean is played. In
the rollouts the rest of the meldingsrunde is bid by the net, whose stik
bids are then its contract guess entirely (net.build: contract_mix 1), each
seat from its own view: no search inside a search. declare_by_simulation
does the same for the melder's trump, ace and fordækt card
(is_declaration). simulating() and SimulatingPlayer are that bot for
evaluation and for a table.

All rollouts and the real runder of an actor are scored in one forward
pass per step (SearchingGames, like actor.BatchedGames), so the GPU sees
batches of hundreds to thousands of states.
"""

import random
import time

import numpy as np

from . import actions as A
from . import cards as C
from . import features as F
from . import meldinger as M
from .actor import BatchedGames, add_samples, score_requests_of, spil_steps
from .spil import expected_outcome, expected_seat_outcomes, outcome
from .agent import NetPlayer, bot_act, explore_bids, net_candidates, net_choice, play_steps, side_stik
from .engine import BIDDING, CHOOSING_TRUMP, PLAYING, IllegalAction, Round
from .tbranch import branch_arrays, points_table, static_packed
from .observation import FACE_DOWN, HIDDEN_DISCARD, HIDDEN_FORDAEKT, PLAY_FACE_DOWN, observe


def _guesses_contract(config):
    """The contract head or the bid net is on (rows for either are made the same way)."""
    return bool(getattr(config, "contract", False) or getattr(config, "bid_net", False))


def enabled(config):
    return bool(getattr(config, "search_share", 0) or getattr(config, "search_share_bid", 0)
                or getattr(config, "bid_by_simulation", False) or getattr(config, "declare_by_simulation", False))


# -- worlds ---------------------------------------------------------------------


def sample_world(r, seat, rng, tries=30):
    """A Round in the same state as r, its hidden cards dealt anew from
    what `seat` may know, or None when `tries` draws found none. The draw
    reads only observe(r, seat); a world is kept only when the runde's
    actions replay legally in it and the seat's observation there is the
    same as in r."""
    obs = observe(r, seat)
    for _ in range(tries):
        world = world_from(obs, r.rules, rng)
        if world is not None and observe(world, seat) == obs:
            return world
    return None


def world_from(obs, rules, rng):
    """One draw: a deal consistent with the observation's cards, counts and
    shown voids, and the log with the hidden cards (others' discards, the
    fordækt card) filled in, replayed (with checks). None when the draw
    breaks a rule. The caller still compares the observation."""
    s = obs["seat"]
    melder = obs["melder"]
    called = obs["called_ace"]
    sol = obs["most_stik"] is not None
    fordaekt = obs["fordaekt"]

    # the stik as the seat saw them: face-up cards per seat, shown voids
    played = [[] for _ in range(4)]
    void = [set() for _ in range(4)]
    stik = [plays for _, plays, _ in obs["tricks"]]
    if obs["trick"]:
        stik.append(obs["trick"])
    for plays in stik:
        lead = plays[0][1]
        led = called if lead == FACE_DOWN else C.suit_of(lead)
        for p, card in plays:
            if card == FACE_DOWN:
                suit = called  # the fordækt card counts as the called ace's suit
            else:
                played[p].append(card)
                suit = C.suit_of(card)
            # a joker into a stik led in a suit shows a void too: holding
            # the suit, the seat had to follow (Anders, 26 October 2026)
            if led >= 0 and suit != led and (suit >= 0 or p != s):
                void[p].add(led)

    # exchanges with the kitty, in order: (seat, its cards or None when hidden, how many)
    exchanges = []
    for actor, action in obs["log"]:
        if isinstance(action, tuple):
            exchanges.append((actor, action, len(action)))
        elif action >= HIDDEN_DISCARD:
            exchanges.append((actor, None, action - HIDDEN_DISCARD))
    kitty = [None] * C.KITTY_SIZE
    taken = {}  # seat -> the kitty positions it took
    position = 0
    for actor, _, n in exchanges:
        taken[actor] = list(range(position, position + n))
        if sol:
            position += n
    for i, card in enumerate(obs["turned"]):
        kitty[i] = card
    for p, card in zip(taken.get(s, ()), obs["kitty_seen"]):
        kitty[p] = card

    own_discards = [card for actor, cards, _ in exchanges if actor == s and cards for card in cards]
    own = set(obs["hand"]) | set(played[s]) | set(own_discards)
    if fordaekt is not None and s == melder and fordaekt["waiting"]:
        own.add(fordaekt["card"])
    own -= set(obs["kitty_seen"])
    if len(own) != C.HAND_SIZE:
        return None

    others = [o for o in range(4) if o != s]
    held = {o: set() for o in others}  # cards the seat knows another seat holds now
    if obs["open_hand"] and melder != s:
        held[melder] |= set(obs["open_hand"])
    for o in others:
        for p in taken.get(o, ()):
            if kitty[p] is not None and kitty[p] not in played[o]:
                held[o].add(kitty[p])
    known = own | set(obs["kitty_seen"]) | set(obs["turned"]) | {c for o in others for c in set(played[o]) | held[o]}
    unseen = [c for c in range(C.DECK_SIZE) if c not in known]

    hidden_fd = fordaekt is not None and s != melder
    groups = []  # [seat or "kitty", what, count, allowed(card) or None]
    for o in others:
        bad = set(void[o])
        if o == melder and fordaekt is not None:
            bad.add(called)  # she was void in the called suit when she laid it
        groups.append([o, "hand", obs["card_counts"][o] - len(held[o]),
                       (lambda c, bad=bad: C.suit_of(c) not in bad) if bad else None])
        hidden = sum(n for actor, cards, n in exchanges if actor == o and cards is None)
        groups.append([o, "discard", hidden, None])
    if hidden_fd:
        groups.append([melder, "fordaekt", 1, lambda c: C.suit_of(c) != called])
    free = [p for p in range(C.KITTY_SIZE) if kitty[p] is None and not any(p in taken[o] for o in taken if o != s)]
    groups.append(["kitty", "rest", len(free), None])
    if any(g[2] < 0 for g in groups) or sum(g[2] for g in groups) != len(unseen):
        return None

    got = {(g[0], g[1]): [] for g in groups}
    pool = set(unseen)
    ace_card = C.ace(called) if called is not None else None
    pinned = None  # the melder took the called ace up from the kitty (selvmakker; the seat cannot tell)
    if ace_card in pool:
        where = _ace_options(obs, groups, taken, kitty, stik, void, rules)
        if not where:
            return None
        group = rng.choices([g for g, _ in where], [n for _, n in where])[0]
        if group == "take":
            group = next(g for g in groups if g[0] == melder and g[1] == "hand")
            pinned = ace_card
        got[(group[0], group[1])].append(ace_card)
        pool.discard(ace_card)
        group[2] -= 1
    if not _deal_out(sorted(pool), groups, got, rng):
        return None
    for p, card in zip(free, got[("kitty", "rest")]):
        kitty[p] = card

    fd_card = got[(melder, "fordaekt")][0] if hidden_fd else None
    hands = [None] * 4
    hands[s] = own
    for o in others:
        pool_o = set(played[o]) | held[o] | set(got[(o, "hand")])
        if o == melder and fd_card is not None:
            pool_o.add(fd_card)
        # the kitty cards it took: any of its cards but those it laid away
        open_positions = [p for p in taken.get(o, ()) if kitty[p] is None]
        if o == melder and ace_card in pool_o and ace_card not in kitty:
            pinned = ace_card  # she played or shows the ace she called: she took it up (or holds all four)
        if open_positions and pinned is not None and o == melder:
            kitty[open_positions.pop(rng.randrange(len(open_positions)))] = pinned
        if open_positions:
            # not the called ace: from the kitty it would make no esmakker (unless pinned above)
            choices = sorted(pool_o - set(obs["turned"]) - {ace_card})
            if len(choices) < len(open_positions):
                return None
            for p, card in zip(open_positions, rng.sample(choices, len(open_positions))):
                kitty[p] = card
        deal_hand = (pool_o | set(got[(o, "discard")])) - {kitty[p] for p in taken.get(o, ())}
        if len(deal_hand) != C.HAND_SIZE:
            return None
        hands[o] = deal_hand
    if None in kitty:
        return None
    deal = [c for o in range(4) for c in sorted(hands[o])] + kitty
    if len(set(deal)) != C.DECK_SIZE:
        return None

    discards = {o: list(got[(o, "discard")]) for o in others}
    log = []
    for actor, action in obs["log"]:
        if isinstance(action, tuple):
            pass
        elif action >= HIDDEN_DISCARD:
            n = action - HIDDEN_DISCARD
            action, discards[actor] = tuple(discards[actor][:n]), discards[actor][n:]
        elif action == HIDDEN_FORDAEKT:
            action = A.FORDAEKT + fd_card
        elif action == PLAY_FACE_DOWN:
            action = A.PLAY + fd_card
        log.append((actor, action))
    try:
        return Round.replay(deal, obs["dealer"], log, rules, check=True)
    except (IllegalAction, ValueError):
        return None


def _deal_out(cards, groups, got, rng):
    """Deals the cards to the groups ([owner, what, count, allowed(card)
    or None]; got[(owner, what)] receives them), every group exactly its
    count and only cards it allows. Card by card in random order, each to
    a group drawn by its free places among those that still leave a
    complete deal possible (a small max-flow over suits), so a deal is
    found whenever one exists. False when none does."""
    rng.shuffle(cards)
    open_groups = [g for g in groups if g[2]]
    if all(g[3] is None for g in open_groups):
        for g in open_groups:
            got[(g[0], g[1])].extend(cards[:g[2]])
            cards = cards[g[2]:]
        return True
    probe = (52, 0, 13, 26, 39)  # a card of each kind: joker, then the suits
    allows = [[g[3] is None or g[3](probe[t]) for t in range(5)] for g in open_groups]
    left = [0] * 5
    for c in cards:
        left[C.suit_of(c) + 1] += 1
    room = [g[2] for g in open_groups]
    if not _feasible(left, room, allows):
        return False
    for c in cards:
        t = C.suit_of(c) + 1
        options = [i for i in range(len(open_groups)) if room[i] and allows[i][t]]
        left[t] -= 1
        while options:
            i = rng.choices(options, [room[j] for j in options])[0]
            room[i] -= 1
            if _feasible(left, room, allows):
                break
            room[i] += 1
            options.remove(i)
        else:
            return False
        got[(open_groups[i][0], open_groups[i][1])].append(c)
    return True


def _feasible(left, room, allows):
    """Whether `left` cards per kind fit the groups' `room` (a max-flow)."""
    need = sum(left)
    if need > sum(room):
        return False
    flow = [[0] * len(room) for _ in range(5)]
    used = [0] * len(room)
    sent = [0] * 5

    def augment(t, seen):
        for i in range(len(room)):
            if allows[i][t] and i not in seen:
                seen.add(i)
                if used[i] < room[i]:
                    used[i] += 1
                    flow[t][i] += 1
                    return True
                for u in range(5):  # push one of u's cards out of group i, if u can go elsewhere
                    if flow[u][i] and augment(u, seen):
                        flow[u][i] -= 1
                        flow[t][i] += 1
                        return True
        return False

    total = 0
    for t in range(5):
        while sent[t] < left[t]:
            if not augment(t, set()):
                return False
            sent[t] += 1
            total += 1
    return total == need


def _ace_options(obs, groups, taken, kitty, stik, void, rules):
    """Where the called ace may lie when the seat has not seen it:
    [(group or "take", weight)], weight the group's free places. "take":
    the melder took it up from the kitty (selvmakker, the seat cannot tell).
    The melder never holds it from the deal (she calls an ace she lacks);
    a seat that showed out of its suit, or played another card in the
    first stik led in its suit, or banked first where the esmakker may not,
    does not hold it."""
    s, melder, called = obs["seat"], obs["melder"], obs["called_ace"]
    e = obs["esmakker"]
    take = sum(1 for p in taken.get(melder, ()) if kitty[p] is None) if melder != s else 0
    melder_take = [("take", take)] if take and called not in void[melder] and obs["fordaekt"] is None else []
    kitty_rest = [(g, g[2]) for g in groups if g[0] == "kitty" and g[2]]
    if obs["selvmakker"]:
        return kitty_rest + melder_take
    no_hand = set()  # seats that cannot hold it now
    for plays in stik:
        lead = plays[0][1]
        if (called if lead == -1 else C.suit_of(lead)) == called:
            no_hand |= {p for p, card in plays if card != -1}
            break
    if obs["banks"] and not rules.esmakker_banks_first:
        no_hand.add(obs["banks"][0])
    options = [(g, g[2]) for g in groups
               if g[0] not in ("kitty", melder) and g[2] and (e is None or g[0] == e)
               and (g[1] == "discard" or (g[1] == "hand" and called not in void[g[0]] and g[0] not in no_hand))]
    if e is not None:  # the esmakker is known and her ace has not fallen: she holds it, or laid it away
        return options
    return options + kitty_rest + melder_take


# -- the search inside the batched actor -------------------------------------------


class _Game:
    __slots__ = ("steps", "request", "parked")

    def __init__(self, steps, request):
        self.steps, self.request = steps, request
        self.parked = False


class _Job:
    """One searched decision: its candidates' rollouts and their results."""
    __slots__ = ("game", "seat", "state", "cands", "points", "q", "finals", "lefts", "pending", "net_choice",
                 "spil", "before", "side", "cf", "simulated", "check", "real")

    def __init__(self, game, seat, state, cands, net_choice, worlds, spil, before):
        self.game, self.seat, self.state, self.cands = game, seat, state, cands
        self.points = np.zeros((len(cands), worlds))  # candidate x world: the runde's points
        self.q = None  # ... and the Q target (with the spil's part), once all are in
        self.finals = np.zeros((len(cands), worlds, 4))  # the spil's totals after each rollout's runde
        self.lefts = np.zeros((len(cands), worlds), np.int64)  # ... and the runder left then
        self.pending = 0
        self.net_choice = net_choice
        self.spil, self.before = spil, before
        self.side = None  # a melder's trump choice for the contract head: the side's stik per rollout
        self.cf = False  # counterfactual contract rows only (no game waits for it, no Q rows)
        self.simulated = False  # bid_by_simulation / declare_by_simulation: the best mean is played, always
        self.check = None  # melder_check: the guess's pick; the cands are the seats tried, points the melder's
        self.real = None  # ... and the real melder


def _points(r, seat):
    return float(r.points()[seat]) if r.complete() else 0.0


def _q_targets(job, config):
    """The job's Q targets (candidate x world) as the learner's
    (actor.spil_steps with spil_target "expected"): each rollout's runde
    points plus spil_weight times the change it made in the seat's expected
    spil outcome, the outcomes of all rollouts with the same runder left
    worked out in one numpy call. Without a spil (a lone runde) just the
    points."""
    if job.spil is None:
        return job.points.copy()
    seat = job.seat
    (m0, w0) = job.before
    margin = np.empty(job.points.shape)
    win = np.empty(job.points.shape)
    for left in np.unique(job.lefts):
        at = job.lefts == left
        if left > 0:
            margin[at], win[at] = expected_seat_outcomes(job.finals[at], int(left), config.runde_sd, seat)
        else:
            ends = [outcome(list(t)) for t in job.finals[at]]
            margin[at] = [m[seat] for m, _ in ends]
            win[at] = [w[seat] for _, w in ends]
    return job.points + config.spil_weight * ((margin - m0[seat]) + config.win_value * (win - w0[seat]))


def is_bid_decision(r, kind):
    """A decision that search_share_bid covers: the meldingsrunde, the
    declaration (trump, ace, vip) and fordækt out of turn."""
    return r.phase != PLAYING or kind == "offer"


def bid_options(cands, numbers=2):
    """What a simulated bid tries (bid_by_simulation): every candidate that
    is not a stik melding (pas, going along), and the stik meldinger of the
    lowest `numbers` melding numbers still legal, every pahæng of them (sol
    too when the net may bid it). The higher ones are tried when the
    meldingsrunde gets there."""
    stik = [a for a in cands if a < A.PAS and not M.is_sol(a - A.BID)]
    out = [a for a in cands if a >= A.PAS or (a < A.PAS and M.is_sol(a - A.BID))]
    if stik:
        lowest = M.number(stik[0] - A.BID)  # legal_actions lists them lowest first
        out += [a for a in stik if M.number(a - A.BID) < lowest + numbers]
    return out


def is_declaration(r, seat, kind, cands):
    """A decision declare_by_simulation searches: the melder's trump and
    called ace (and any other choice before the card play but a discard),
    fordækt out of turn, and the melder's first lead when it may lay a
    fordækt card there (the forhånd)."""
    if kind == "discard":
        return False
    if kind == "offer" or r.phase not in (BIDDING, PLAYING):
        return True
    return (r.phase == PLAYING and seat == r.melder and not r.tricks and not r.trick
            and any(A.FORDAEKT <= a < A.ACTION_COUNT for a in cands))


class SearchingGames(BatchedGames):
    """BatchedGames with search: runder whose decision is searched wait
    ("parked") while their rollouts are played in the same batches.
    refill=False plays only the runder it starts with (sync mode)."""

    def __init__(self, model, device, rng, config, partner, rules, refill=True, games=None, source=None,
                 scorer=None, rollouts=None):
        """source: an iterator of generators like agent.play_steps to play
        instead of new self-play spil (evaluation); what they return is then
        kept in self.completed. scorer: as BatchedGames. rollouts: with
        config search_gpu_rollouts, rollouts(arrays, packed, index) -> runde
        points [n, 4] plays the rollouts' card play on the GPU
        (trollout.Rollouts.points_arrays, or the inference server's)."""
        self.gpu_rollouts = rollouts if getattr(config, "search_gpu_rollouts", False) else None
        self.to_gpu = []  # [job, index, round, spil, offered]: rollouts for the GPU, played at the step's end
        self.greedy = NetPlayer(model, 0.0, rng)
        self.source = source
        self.completed = []
        self.rollouts = []  # [job, candidate index, world, steps, request]
        self.refill = refill
        self.stats = {"searched": 0, "searched_bid": 0, "rollouts": 0, "changed": 0, "gain": 0.0,
                      "no_world": 0, "rollout_seconds": 0.0}
        # the counterfactual rows draw their worlds from their own stream, so
        # turning them on leaves the runder and the other searches as they were
        self.cf_rng = random.Random(hash(rng.getstate()))
        # bid_sim_share: which runder bid by simulation, drawn once per runde
        # from a stream of its own; {id(Round): (Round, simulated)}
        self.sim_rng = random.Random(hash(rng.getstate()) + 1)
        self.sim_runder = {}
        if games is not None:
            config = _with(config, actor_games=games)
        if getattr(config, "bid_by_simulation", False) and config.bid_epsilon:
            config = _with(config, bid_epsilon=0.0)  # the net never bids on its own, not even at random
        super().__init__(model, device, rng, config, partner, rules, scorer)

    def start(self):
        if self.source is not None:
            steps = next(self.source, None)
            if steps is None:
                return None
        else:
            steps = spil_steps(self.model, self.rng, self.config, self.partner, self.rules)
        try:
            return _Game(steps, next(steps))
        except StopIteration as done:
            self.finished.append(done.value)
            return None

    def done(self):
        """No runde left to play (refill=False, or a source run dry)."""
        if self.source is not None:
            for i, g in enumerate(self.games):
                if g is None:
                    self.games[i] = self.start()
        return not self.rollouts and not self.to_gpu and not self.finished and all(g is None for g in self.games)

    def step(self, batch):
        if self.refill:
            for i, g in enumerate(self.games):
                if g is None:
                    self.games[i] = self.start()
        live = [g for g in self.games if g is not None and not g.parked]
        requests = [g.request for g in live] + [ro[4] for ro in self.rollouts]
        if requests:
            q, best = self._score(requests)
            start = 0
            rollouts, self.rollouts = self.rollouts, []
            for i, game in enumerate(live):
                cands = game.request[2]
                values = q[start:start + len(cands)]
                start += len(cands)
                self._counterfactual(game, batch)
                self._melder_check(game, batch)
                if not self._search(game, values, batch):
                    self._advance(game, cands[best[i]])
            for i, ro in enumerate(rollouts, len(live)):
                cands = ro[4][2]
                try:
                    ro[4] = ro[3].send(cands[best[i]])
                    self._keep(ro)
                except StopIteration:
                    self._result(ro[0], ro[1], ro[2], batch)
        if self.to_gpu and (len(self.to_gpu) >= getattr(self.config, "search_gpu_batch", 1) or not self._cpu_work()):
            self._play_on_gpu(batch)
        for value in self.finished:
            if self.source is not None:
                self.completed.append(value)
            else:
                add_samples(value, batch)
        self.finished = []
        if not self.refill:
            self.games = [g for g in self.games if g is not None] or [None]

    def _cpu_work(self):
        """Whether a step has anything to play but the rollouts waiting for
        the GPU: a runde not waiting for its search, a CPU rollout, a place
        for a new spil."""
        return bool(self.rollouts) or any(g is not None and not g.parked for g in self.games) or (
            self.refill and any(g is None for g in self.games))

    def _score(self, requests):
        """(every candidate's Q, each request's best candidate index); a
        league seat's decisions by its earlier snapshot (actor.LeaguePlayer)."""
        return score_requests_of(self.scorer, requests)

    def _advance(self, game, action):
        try:
            game.request = game.steps.send(action)
        except StopIteration as done:
            self.finished.append(done.value)
            self.games[self.games.index(game)] = None

    def _search(self, game, values, batch):
        """Starts a search at the game's decision when it is drawn; True
        when the game now waits for its rollouts."""
        c = self.config
        player, state, cands, (r, seat, kind, game_players, bidders, spil) = game.request
        if kind == "discard" or len(cands) < 2 or getattr(player, "league", False):
            return False
        bid = is_bid_decision(r, kind)
        simulated = self._simulated(r, seat, kind, cands)
        if not simulated:
            share = c.search_share_bid if bid else c.search_share
            if not share or self.rng.random() >= share:
                return False
        t0 = time.perf_counter()
        belief = getattr(c, "search_belief", 0)
        count = c.bid_sim_worlds if simulated else c.search_worlds
        draws = count * max(1, belief)
        worlds = [w for w in (sample_world(r, seat, self.rng) for _ in range(draws)) if w is not None]
        if worlds and belief > 1:
            weights = self._bid_likelihood(worlds, seat, game_players, bidders, spil)
            worlds = self.rng.choices(worlds, weights, k=count)
        if not worlds:
            self.stats["no_world"] += 1
            return False
        order = [int(i) for i in np.argsort(-values, kind="stable")]
        gumbel = c.search_gumbel_k if r.phase == BIDDING else getattr(c, "search_gumbel_k_play", 0)
        if simulated == "bid":
            chosen = bid_options(cands, c.bid_sim_numbers)
        elif simulated and len(cands) <= c.declare_sim_max:
            chosen = list(cands)
        elif gumbel:
            chosen = self._gumbel_top(cands, values, gumbel, c.search_gumbel_tau)
            if cands[order[0]] not in chosen:
                chosen.append(cands[order[0]])  # the net's own choice, to compare with
        else:
            chosen = [cands[i] for i in order[:c.search_k]]
            rest = [cands[i] for i in order[c.search_k:]]
            if c.search_random and rest:
                chosen += self.rng.sample(rest, min(c.search_random, len(rest)))
        if r.phase == BIDDING and getattr(c, "search_bid_lowest", 0) and not simulated:
            # pas, the next few stik meldinger up and the plain ones up to
            # search_bid_up_to are always tried, whatever the net thinks of
            # them: a net that never bids never learns what a bid is worth
            # (Anders: "test alle ... se hvad der vinder og forstærk den gren");
            # sol only a search_bid_sol share of the time
            tried = explore_bids(cands, c.search_bid_lowest, self.rng, c.search_bid_sol, c.search_bid_up_to)
            chosen += [a for a in tried if a not in chosen]
        if r.phase == BIDDING and getattr(c, "search_bid_pas", False) and A.PAS in cands and A.PAS not in chosen:
            chosen.append(A.PAS)  # a bid is worth what it beats: the others having the melding
        if simulated and len(chosen) < 2:
            if chosen:
                self._advance(game, chosen[0])  # one option: played as it is
                return True
            return False
        before = expected_outcome(spil.totals, spil.left, c.runde_sd) if spil is not None else None
        net_choice = cands[order[0]] if not simulated or cands[order[0]] in chosen else chosen[0]
        job = _Job(game, seat, state, chosen, net_choice, len(worlds), spil, before)
        job.simulated = bool(simulated)
        if simulated:
            self.stats["simulated_" + simulated] = self.stats.get("simulated_" + simulated, 0) + 1
        if (_guesses_contract(c) and getattr(c, "contract_search", True) and r.phase == CHOOSING_TRUMP
                and seat == r.melder and all(A.TRUMP <= a < A.ACE for a in chosen)):
            job.side = np.full((len(chosen), len(worlds)), -1, np.int64)
        game.parked = True
        self.stats["searched"] += 1
        self.stats["searched_bid"] += bid
        players = [self.greedy if isinstance(p, NetPlayer) else p for p in game_players]
        job.pending = len(worlds) * len(chosen)  # all of them before any can finish
        for wi, world in enumerate(worlds):
            for ci, action in enumerate(chosen):
                w = world.clone()
                if action != F.NO_FORDAEKT:
                    w.apply(seat, action, check=False)
                steps = play_steps(w, players, (), bidders=bidders, spil=spil, offered=kind == "offer")
                self.stats["rollouts"] += 1
                try:
                    self._keep([job, (ci, wi), w, steps, next(steps)])
                except StopIteration:
                    self._result(job, (ci, wi), w, batch)
        self.stats["rollout_seconds"] += time.perf_counter() - t0
        return True

    def _sim_runde(self, r):
        """Whether this runde bids by simulation: all of them, or a
        bid_sim_share of them in training (Anders: "simulering i kun nogle
        runder. ja 30%"); the others bid by the net's contract guess alone,
        which the simulated ones and the counterfactual rows teach."""
        share = getattr(self.config, "bid_sim_share", 1.0)
        if share >= 1:
            return True
        entry = self.sim_runder.get(id(r))
        if entry is None or entry[0] is not r:
            if len(self.sim_runder) > 4 * max(1, self.config.actor_games):
                self.sim_runder = {k: e for k, e in self.sim_runder.items() if not e[0].complete()}
            entry = self.sim_runder[id(r)] = (r, self.sim_rng.random() < share)
        return entry[1]

    def _simulated(self, r, seat, kind, cands):
        """"bid" or "declare" when the decision is always searched and its
        best mean played (bid_by_simulation, declare_by_simulation), else
        None."""
        c = self.config
        if r.phase == BIDDING:
            return "bid" if c.bid_by_simulation and self._sim_runde(r) else None
        if c.declare_by_simulation and is_declaration(r, seat, kind, cands):
            return "declare"
        return None

    def _melder_check(self, game, batch):
        """config melder_check_share: at the real melder's trump choice of a
        net-only runde, every seat is also played as melder on the real deal
        (the seats before it pass, it bids the lowest plain melding, so all
        four at the same contract; each trump, the net at every seat);
        counters melder_check_same: how often the seat the contract guess
        rates highest (each seat at its bid of that same contract, from what
        it knows) is the seat that would score most as melder (Anders: the
        guess must be pulled toward the simulation); melder_check_real: how
        often the real melder is, which the meldingsrunde's order also decides.
        A check of the guess, on the true cards: it does not change what is
        played or learned."""
        c = self.config
        if not c.melder_check_share:
            return
        _, _, _, (r, seat, kind, game_players, bidders, spil) = game.request
        if r.phase != CHOOSING_TRUMP or seat != r.melder or kind != "act" or bidders is not None:
            return
        if not all(isinstance(p, NetPlayer) for p in game_players):
            return
        if self.cf_rng.random() >= c.melder_check_share:
            return
        rounds, tried, asks = [], [], []
        for s in range(4):
            # every seat at the same contract: the seats before it pass (with the real bids before
            # it standing, a later seat had to bid higher than the forhånd, and the real melder,
            # who won by bidding over the others, was tried at the hardest contract of the four:
            # it came out "strongest" in 17 % of the checks, under the 25 % of chance)
            w = Round(r.deal, r.dealer, r.rules)
            while w.phase == BIDDING and w.to_act() != s:
                w.apply(w.to_act(), A.PAS, check=False)
            if w.phase != BIDDING or w.to_act() != s:
                continue
            bids = [a for a in w.legal_actions(s) if a < A.PAS and M.pahaeng(a - A.BID) == M.NONE]
            state = F.to_bytes(F.encode(w, s, 0, spil))
            if bids and won_melding(w, s):
                asks.append((s, state, bids[0]))
                for trump in w.legal_actions(s):
                    t = w.clone()
                    t.apply(s, trump, check=False)
                    rounds.append(t)
                    tried.append(s)
        if not rounds:
            return
        # the seat the guess rates highest at that bid: the bid's value is its guess (contract_mix 1)
        q, _ = self._score([(None, state, [bid]) for _, state, bid in asks])
        job = _Job(None, seat, None, tried, None, 1, None, None)
        job.check = asks[int(np.argmax(q))][0]
        job.real = r.melder
        job.pending = len(rounds)
        self.stats["melder_check_rollouts"] = self.stats.get("melder_check_rollouts", 0) + len(rounds)
        for ci, t in enumerate(rounds):
            steps = play_steps(t, [self.greedy] * 4, (), spil=spil)
            try:
                self._keep([job, (ci, 0), t, steps, next(steps)])
            except StopIteration:
                self._result(job, (ci, 0), t, batch)

    def _counterfactual(self, game, batch):
        """config contract_cf: at the seat's first bid of a net-only runde,
        the side's stik if the seat became melder, for each trump, in
        contract_cf_worlds worlds (rollouts like a search's, on the GPU with
        search_gpu_rollouts); each a contract row at the seat's state."""
        c = self.config
        if not (getattr(c, "contract_cf", False) and _guesses_contract(c)):
            return
        player, state, _, (r, seat, _, game_players, bidders, spil) = game.request
        if (r.phase != BIDDING or bidders is not None or any(s == seat for s, _ in r.history)
                or getattr(player, "league", False)):
            return
        if not all(isinstance(p, NetPlayer) for p in game_players):
            return
        if c.contract_cf_share < 1 and self.cf_rng.random() >= c.contract_cf_share:
            return
        worlds = []
        for _ in range(max(1, c.contract_cf_worlds)):
            w = sample_world(r, seat, self.cf_rng)
            if w is not None and won_melding(w, seat):
                worlds.append(w)
        if not worlds:
            self.stats["cf_no_world"] = self.stats.get("cf_no_world", 0) + 1
            return
        trumps = worlds[0].legal_actions(seat)
        job = _Job(None, seat, state, trumps, None, len(worlds), None, None)
        job.cf = True
        job.side = np.full((len(trumps), len(worlds)), -1, np.int64)
        job.pending = len(worlds) * len(trumps)
        players = [self.greedy] * 4
        self.stats["cf"] = self.stats.get("cf", 0) + 1
        self.stats["cf_rollouts"] = self.stats.get("cf_rollouts", 0) + job.pending
        for wi, world in enumerate(worlds):
            for ci, trump in enumerate(trumps):
                w = world.clone()
                w.apply(seat, trump, check=False)
                steps = play_steps(w, players, (), spil=spil)
                try:
                    self._keep([job, (ci, wi), w, steps, next(steps)])
                except StopIteration:
                    self._result(job, (ci, wi), w, batch)

    def _keep(self, ro):
        """A rollout waiting for its next decision: on the GPU from here
        (search_gpu_rollouts) once it is in the card play of a stik melding
        with the net at every seat, which is all the GPU plays (trollout);
        else on with the CPU."""
        if self.gpu_rollouts is not None:
            r, _, kind, players, _, spil = ro[4][3]
            if r.phase == PLAYING and r.kind == "stik" and all(isinstance(p, NetPlayer) for p in players):
                # waiting at the fordækt offer: not asked yet; at a card: asked, or never to be
                self.to_gpu.append([ro[0], ro[1], r, spil, kind != "offer"])
                return
        self.rollouts.append(ro)

    def _play_on_gpu(self, batch):
        """Plays the rollouts handed to the GPU this step and takes their results."""
        branches, self.to_gpu = self.to_gpu, []
        rounds = [b[2] for b in branches]
        t0 = time.perf_counter()
        arrays = branch_arrays(rounds, [b[4] for b in branches])
        packed = static_packed(rounds, [b[3] for b in branches])
        t1 = time.perf_counter()
        points = self.gpu_rollouts(arrays, *packed)
        st = self.stats
        st["gpu_rollouts"] = st.get("gpu_rollouts", 0) + len(branches)
        st["gpu_calls"] = st.get("gpu_calls", 0) + 1
        st["gpu_export_seconds"] = st.get("gpu_export_seconds", 0.0) + t1 - t0
        st["gpu_seconds"] = st.get("gpu_seconds", 0.0) + time.perf_counter() - t1
        for (job, index, r, _, _), row in zip(branches, points):
            self._result(job, index, r, batch, row)

    def _gumbel_top(self, cands, values, k, tau):
        """k candidates drawn without replacement with chance softmax(Q /
        tau) (tau in points), by the Gumbel-top-k trick as in Gumbel
        AlphaZero (Danihelka et al. 2022): the net's favourites are drawn most,
        but every legal action now and then, so a melding the net has given
        up on is still tried, with no knowledge of the game put in."""
        scale = float(self.model.points_scale)
        u = np.array([self.rng.random() for _ in cands]).clip(1e-12, 1 - 1e-12)
        keys = np.asarray(values, np.float64) * (scale / tau) - np.log(-np.log(u))
        return [cands[int(i)] for i in np.argsort(-keys, kind="stable")[:k]]

    def _bid_likelihood(self, worlds, seat, players, bidders, spil):
        """How well each world explains the other seats' bids: the world is
        replayed through the meldingsrunde and each bid another seat made is
        compared with what its player (the net greedy, or the bot) would bid
        there with the cards the world gives it; each bid it would not have
        made multiplies the weight by search_belief_miss. Uniform worlds
        ignore what the bids say about the hands; this weighs them
        (importance resampling toward the seat's belief)."""
        miss = self.config.search_belief_miss
        mismatches = [0] * len(worlds)
        asks = []  # (world index, state, candidates, the bid made)
        for i, world in enumerate(worlds):
            step = Round(world.deal, world.dealer, world.rules)
            for actor, action in world.log:
                if step.phase != BIDDING:
                    break
                if actor != seat:
                    player = bidders[actor] if bidders is not None else players[actor]
                    if isinstance(player, NetPlayer):
                        cands = net_candidates(self.model, step, actor)
                        if len(cands) > 1:
                            asks.append((i, F.to_bytes(F.encode(step, actor, 0, spil)), cands, action))
                    elif bot_act(player, step, actor) != action:
                        mismatches[i] += 1
                step.apply(actor, action, check=False)
        if asks:
            _, best = self._score([(None, state, cands) for _, state, cands, _ in asks])
            for (i, _, cands, action), b in zip(asks, best):
                if cands[b] != action:
                    mismatches[i] += 1
        self.stats["belief_mismatch"] = self.stats.get("belief_mismatch", 0) + sum(mismatches)
        return [miss ** m for m in mismatches]

    def _result(self, job, index, world, batch, gpu_points=None):
        """A rollout's end: `world` played out on the CPU, or its runde
        points per seat from the GPU (gpu_points; the runde complete)."""
        c = self.config
        if job.check is not None:  # the melder's points: each try has its own
            melder = world.melder
            job.points[index] = _points(world, melder) if gpu_points is None else float(gpu_points[melder])
            job.pending -= 1
            if not job.pending:
                best = {}
                for s, p in zip(job.cands, job.points[:, 0]):
                    best[s] = max(best.get(s, float("-inf")), float(p))
                strongest = max(best, key=best.get)
                batch.count("melder_check", 1)
                batch.count("melder_check_same", int(strongest == job.check))
                batch.count("melder_check_real", int(strongest == job.real))
            return
        job.points[index] = _points(world, job.seat) if gpu_points is None else float(gpu_points[job.seat])
        if job.side is not None:
            job.side[index] = _side_stik(world, gpu_points)
        if job.spil is not None:
            totals, left = job.spil.totals, job.spil.left
            if gpu_points is not None:
                totals = [t + float(p) for t, p in zip(totals, gpu_points)]
                left -= 1
            elif world.complete():
                totals = [t + float(p) for t, p in zip(totals, world.points())]
                left -= 1
            job.finals[index], job.lefts[index] = totals, left
        job.pending -= 1
        if job.pending:
            return
        if job.cf:
            for action, sides in zip(job.cands, job.side):
                for side in sides[sides >= 0]:
                    batch.add_contract_row(job.state, action, action - A.TRUMP, int(side))
            return
        job.q = _q_targets(job, c)
        means = job.q.mean(axis=1)
        for action, points, mean in zip(job.cands, job.points.mean(axis=1), means):
            batch.add_search_row(job.state, action, float(points), float(mean), c.search_weight)
        if job.side is not None:
            for action, sides in zip(job.cands, job.side):
                for side in sides[sides >= 0]:
                    batch.add_contract_row(job.state, action, action - A.TRUMP, int(side))
        best = int(np.argmax(means))
        net = job.cands.index(job.net_choice)
        diff = job.q[best] - job.q[net]  # paired: the same worlds
        se = diff.std(ddof=1) / np.sqrt(len(diff)) if len(diff) > 1 else 0.0
        if not job.simulated and best != net and diff.mean() <= c.search_play_z * se:
            best = net  # not clearly better than the net's own choice: the max of noisy means flatters
        self.stats["changed"] += best != net
        self.stats["gain"] += float(means[best] - means[net])
        if not job.simulated and c.search_explore and self.rng.random() < c.search_explore:
            best = self.rng.randrange(len(job.cands))
        batch.searched += 1
        job.game.parked = False
        self._advance(job.game, job.cands[best])


def won_melding(world, seat):
    """Makes `seat` the melder in `world` (in place; it is at the seat's
    bid): the seat bids the lowest plain stik melding it may, every other
    seat passes. True when the seat now chooses trump; False when it has no
    such bid (the melding is already too high)."""
    bids = [a for a in world.legal_actions(seat) if a < A.PAS and M.pahaeng(a - A.BID) == M.NONE]
    if not bids:
        return False
    world.apply(seat, bids[0], check=False)  # legal_actions lists them lowest first
    while world.phase == BIDDING and world.bid_to_act is not None and world.bid_to_act != seat:
        world.apply(world.bid_to_act, A.PAS, check=False)
    return world.phase == CHOOSING_TRUMP and world.melder == seat


def _side_stik(world, gpu_points=None):
    """The stik the melder's side took in a rollout's runde, or -1 when it
    was not played out (a redeal). From the GPU only the runde's points come
    back: the melder's points grow with every stik the side takes, so the
    row of the runde's point table (tbranch.points_table, the Round at the
    start of the card play) that gives them says how many."""
    if gpu_points is None:
        return side_stik(world) if world.complete() and world.kind == "stik" else -1
    table = np.asarray(points_table(world))
    return int(np.argmin(np.abs(table[:, world.melder] - float(gpu_points[world.melder]))))


def _with(config, **changes):
    from dataclasses import replace
    return replace(config, **changes)


def play_searched(model, rng, config, partner, rules, batch, runder):
    """Sync mode (learner.sync_round): whole spil with search on the CPU,
    one at a time, until `runder` runder (at least one spil)."""
    import torch
    while batch.runder < runder:
        games = SearchingGames(model, torch.device("cpu"), rng, config, partner, rules, refill=False, games=1)
        while not games.done():
            games.step(batch)


def simulating(config, worlds=None):
    """The config of the bot that melder by simulation and plays the rest
    with the net alone ("net + simulation", at the table and in evaluation):
    every bid and declaration searched (bid_by_simulation,
    declare_by_simulation) in `worlds` worlds (default bid_sim_worlds), no
    other search, no exploration, no rows made for learning. Play a source
    of runder with SearchingGames(..., source=...) under it, as policy_eval
    does, to evaluate many runder at once."""
    return _with(config, bid_by_simulation=True, declare_by_simulation=True, bid_sim_share=1.0,
                 bid_sim_worlds=worlds or config.bid_sim_worlds, search_share=0.0, search_share_bid=0.0,
                 search_explore=0.0, epsilon=0.0, bid_epsilon=0.0, contract_cf=False, melder_check_share=0.0)


class SimulatingPlayer(NetPlayer):
    """A NetPlayer that melder by simulation (one decision at a time, for a
    table or explain): at a bid or a declaration it plays its options out
    in `worlds` worlds (simulating(config, worlds)) and takes the best mean;
    the card play is the net's alone. `rollouts` as SearchingGames' (the GPU's
    card play), else on the CPU."""

    def __init__(self, model, config=None, worlds=None, rng=None, device="cpu", rollouts=None):
        """config None: the house defaults with the model's own (contract
        head, no_sol), as for a snapshot at a table or on the ladder;
        worlds None: config.bid_sim_worlds (16; a table takes 100)."""
        super().__init__(model, 0.0, rng or random.Random(0))
        if config is None:
            from .config import Config
            config = Config(contract=getattr(model, "contract", None) is not None,
                            bid_net=getattr(model, "bid", None) is not None,
                            no_sol=bool(getattr(model, "no_sol", False)))
        self.config = simulating(config, worlds)
        self.device, self.gpu = device, rollouts

    def decide(self, r, seat, chosen=(), spil=None):
        action, state, cands, choice = super().decide(r, seat, chosen, spil)
        if action is not None or chosen or r.discard_size(seat):
            return action, state, cands, choice  # a discard is the net's, card by card
        kind = "offer" if F.NO_FORDAEKT in cands else "act"
        if r.phase != BIDDING and not is_declaration(r, seat, kind, cands):
            return action, state, cands, choice
        return self.simulate(r, seat, kind, spil), state, cands, choice

    def simulate(self, r, seat, kind, spil=None):
        """The best option at the seat's decision by the simulation."""
        import torch
        from .actor import Batch
        greedy = NetPlayer(self.model, 0.0, self.rng)
        players = [greedy] * 4

        def one():
            action, _, _ = yield from net_choice(greedy, r, seat, spil=spil, where=(r, seat, kind, players, None, spil))
            return action

        games = SearchingGames(self.model, torch.device(self.device), self.rng, self.config, None, r.rules,
                               refill=False, games=1, source=iter([one()]), rollouts=self.gpu)
        batch = Batch()
        while not games.done():
            games.step(batch)
        self.last_stats = dict(games.stats)
        return games.completed[0]


def policy_eval(model, config, deals=200, seed=3, device="cpu", bid_only=True):
    """Is the search's choice better than the net's? Same-hand duplicate
    at a Svær table: each deal is played once per seat with the net there
    (greedy), once without search and once searching every decision that
    search_share_bid covers (and, unless bid_only, every play decision).
    Returns the net's points per runde both ways and the paired
    difference (search - net) with a 95 % interval."""
    import torch
    from .actor import Batch
    from .partners import factory
    from .rules import STANDARD
    from .selfplay import random_deal
    deal_rng = random.Random(seed)
    specs = []
    for _ in range(deals):
        deal, dealer = random_deal(deal_rng), deal_rng.randrange(4)
        specs += [(deal, dealer, seat) for seat in range(4)]
    svaer = factory("svaer")(0)
    points, melder, stats = {}, {}, {}
    for searching in (False, True):
        cfg = _with(config, search_share_bid=1.0 if searching else 0.0,
                    search_share=0.0 if bid_only or not searching else 1.0, search_explore=0.0, epsilon=0.0,
                    bid_epsilon=0.0)
        rng = random.Random(seed + 1)
        net = NetPlayer(model, 0.0, rng)

        keys = {}

        def runde(r, players, seat):
            yield from play_steps(r, players, (seat,))
            return r

        def source():
            for index, (deal, dealer, seat) in enumerate(specs):
                players = [svaer] * 4
                players[seat] = net
                r = Round(deal, dealer, STANDARD)
                keys[id(r)] = (index, seat)
                yield runde(r, players, seat)
        games = SearchingGames(model, torch.device(device), rng, cfg, None, STANDARD, games=256, source=source())
        batch = Batch()
        while not games.done():
            games.step(batch)
        points[searching] = {keys[id(r)][0]: _points(r, keys[id(r)][1]) for r in games.completed}
        melder[searching] = [r.melder == keys[id(r)][1] for r in games.completed]
        stats[searching] = dict(games.stats)
    keys = sorted(points[False])
    diffs = np.array([points[True][k] - points[False][k] for k in keys])
    return {"deals": deals, "runder": len(keys), "net": float(np.mean([points[False][k] for k in keys])),
            "search": float(np.mean([points[True][k] for k in keys])), "diff": float(diffs.mean()),
            "ci95": float(1.96 * diffs.std(ddof=1) / np.sqrt(len(diffs))),
            "net_melder": float(np.mean(melder[False])), "search_melder": float(np.mean(melder[True])),
            "searched": stats[True]["searched"], "changed": stats[True]["changed"]}


# -- measuring --------------------------------------------------------------------


def bench(weights, device="auto", seconds=60.0, games=256, seed=1, settings=()):
    """Plays with search for `seconds` in this process and reports the
    cost: runder/s, searched decisions/s, rollouts/s, and how often search
    changed the net's choice and by how many points (its own estimate)."""
    import torch
    from .actor import Batch, rules_of, tune_gc
    from .config import Config
    from .learner import load_weights
    from .net import pick_device
    from .partners import factory
    model, d = load_weights(weights)
    config = Config.from_dict(d["config"]).override(settings)
    dev = pick_device(device)
    model = model.to(dev).eval()
    torch.set_num_threads(1)
    rng = random.Random(seed)
    games = SearchingGames(model, dev, rng, config, factory(config.partner), rules_of(config), games=games)
    batch = Batch()
    tune_gc()  # as in an actor
    t0 = time.time()
    steps = 0
    while time.time() - t0 < seconds:
        games.step(batch)
        steps += 1
    dt = time.time() - t0
    st = games.stats
    done = max(batch.searched, 1)
    return {"seconds": round(dt, 1), "runder_per_s": round(batch.runder / dt, 2),
            "searched_per_s": round(batch.searched / dt, 2), "rollouts_per_s": round(st["rollouts"] / dt, 1),
            "samples_per_s": round(len(batch) / dt, 1), "steps_per_s": round(steps / dt, 1),
            "searched": batch.searched, "searched_bid": st["searched_bid"], "no_world": st["no_world"],
            "changed_share": round(st["changed"] / done, 3), "gain_per_search": round(st["gain"] / done, 3),
            "world_sampling_seconds": round(st["rollout_seconds"], 1)}


if __name__ == "__main__":
    import argparse
    import json
    parser = argparse.ArgumentParser(prog="python -m esmakker_ai.search", description="measure search's cost")
    parser.add_argument("weights")
    parser.add_argument("--device", default="auto")
    parser.add_argument("--seconds", type=float, default=60)
    parser.add_argument("--games", type=int, default=256)
    parser.add_argument("--set", action="append", default=[], metavar="KEY=VALUE")
    args = parser.parse_args()
    print(json.dumps(bench(args.weights, args.device, args.seconds, args.games, settings=args.set), indent=2))
