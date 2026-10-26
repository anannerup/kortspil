"""Search in self-play: rollout targets (expert iteration, determinized
search). Anders: "lad den prøve flere forskellige træk fra en kandidatliste
og så over tid danne heuristikker over hvad der virker bedst i en given
situation."

At a share of the net's decisions (config search_share; search_share_bid
in the meldingsrunde, the declaration and fordækt out of turn) the actor
does not just play the net's best action. It takes the net's top
search_k candidates by Q (plus search_random others at random, and in
the meldingsrunde pas and the search_bid_lowest lowest legal meldinger,
whatever their Q), samples search_worlds worlds the deciding seat cannot
tell from the real one (sample_world), and in each world plays every
candidate and then the rest of the runde out: the net greedy on the net's
seats, the partner bot (Svær) where the real game has it. Each candidate's average runde points over the
worlds (the same worlds for every candidate) becomes a Q target for that
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

All rollouts and the real runder of an actor are scored in one forward
pass per step (SearchingGames, like actor.BatchedGames), so the GPU sees
batches of hundreds to thousands of states.
"""

import random
import time

import numpy as np
import torch

from . import actions as A
from . import cards as C
from . import features as F
from .actor import BatchedGames, add_samples, spil_steps
from .agent import spil_targets
from .spil import expected_outcome
from .agent import NetPlayer, explore_bids, play_steps
from .engine import BIDDING, PLAYING, IllegalAction, Round
from .net import unpack
from .observation import FACE_DOWN, HIDDEN_DISCARD, HIDDEN_FORDAEKT, PLAY_FACE_DOWN, observe


def enabled(config):
    return bool(getattr(config, "search_share", 0) or getattr(config, "search_share_bid", 0))


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
    __slots__ = ("game", "seat", "state", "cands", "points", "q", "pending", "net_choice", "spil", "before")

    def __init__(self, game, seat, state, cands, net_choice, worlds, spil, before):
        self.game, self.seat, self.state, self.cands = game, seat, state, cands
        self.points = np.zeros((len(cands), worlds))  # candidate x world: the runde's points
        self.q = np.zeros((len(cands), worlds))  # ... and the Q target (with the spil's part)
        self.pending = 0
        self.net_choice = net_choice
        self.spil, self.before = spil, before


def _points(r, seat):
    return float(r.points()[seat]) if r.complete() else 0.0


def _q_target(r, seat, spil, before, config):
    """The rollout's Q target as the learner's (actor.spil_steps with
    spil_target "expected"): the runde's points plus spil_weight times the
    change it made in the seat's expected spil outcome. Without a spil
    (a lone runde) just the points."""
    points = _points(r, seat)
    if spil is None:
        return points
    totals, left = spil.totals, spil.left
    if r.complete():
        totals = [t + float(p) for t, p in zip(totals, r.points())]
        left -= 1
    after = expected_outcome(totals, left, config.runde_sd)
    return spil_targets(points, before, after, seat, config)


def is_bid_decision(r, kind):
    """A decision that search_share_bid covers: the meldingsrunde, the
    declaration (trump, ace, vip) and fordækt out of turn."""
    return r.phase != PLAYING or kind == "offer"


class SearchingGames(BatchedGames):
    """BatchedGames with search: runder whose decision is searched wait
    ("parked") while their rollouts are played in the same batches.
    refill=False plays only the runder it starts with (sync mode)."""

    def __init__(self, model, device, rng, config, partner, rules, refill=True, games=None, source=None):
        """source: an iterator of generators like agent.play_steps to play
        instead of new self-play spil (evaluation); what they return is then
        kept in self.completed."""
        self.greedy = NetPlayer(model, 0.0, rng)
        self.source = source
        self.completed = []
        self.rollouts = []  # [job, candidate index, world, steps, request]
        self.refill = refill
        self.stats = {"searched": 0, "searched_bid": 0, "rollouts": 0, "changed": 0, "gain": 0.0,
                      "no_world": 0, "rollout_seconds": 0.0}
        if games is not None:
            config = _with(config, actor_games=games)
        super().__init__(model, device, rng, config, partner, rules)

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
        return not self.rollouts and not self.finished and all(g is None for g in self.games)

    def step(self, batch):
        if self.refill:
            for i, g in enumerate(self.games):
                if g is None:
                    self.games[i] = self.start()
        live = [g for g in self.games if g is not None and not g.parked]
        requests = [g.request for g in live] + [ro[4] for ro in self.rollouts]
        if requests:
            q = self._score(requests)
            start = 0
            rollouts, self.rollouts = self.rollouts, []
            for game in live:
                cands = game.request[2]
                values = q[start:start + len(cands)]
                start += len(cands)
                if not self._search(game, values, batch):
                    self._advance(game, cands[int(np.argmax(values))])
            for ro in rollouts:
                cands = ro[4][2]
                values = q[start:start + len(cands)]
                start += len(cands)
                try:
                    ro[4] = ro[3].send(cands[int(np.argmax(values))])
                    self.rollouts.append(ro)
                except StopIteration:
                    self._result(ro[0], ro[1], ro[2], batch)
        for value in self.finished:
            if self.source is not None:
                self.completed.append(value)
            else:
                add_samples(value, batch)
        self.finished = []
        if not self.refill:
            self.games = [g for g in self.games if g is not None] or [None]

    def _score(self, requests):
        states = np.frombuffer(b"".join(req[1] for req in requests), np.uint8).reshape(len(requests), -1)
        counts = torch.tensor([len(req[2]) for req in requests], device=self.device)
        with torch.inference_mode():
            s = torch.from_numpy(unpack(states)).to(self.device, non_blocking=True)
            h = self.model.encode_state(s).repeat_interleave(counts, dim=0)
            a = self.actions[torch.tensor([x for req in requests for x in req[2]], device=self.device)]
            return self.model.q_values(h, a).cpu().numpy()

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
        _, state, cands, (r, seat, kind, game_players, bidders, spil) = game.request
        if kind == "discard" or len(cands) < 2:
            return False
        bid = is_bid_decision(r, kind)
        share = c.search_share_bid if bid else c.search_share
        if not share or self.rng.random() >= share:
            return False
        t0 = time.perf_counter()
        belief = getattr(c, "search_belief", 0)
        draws = c.search_worlds * max(1, belief)
        worlds = [w for w in (sample_world(r, seat, self.rng) for _ in range(draws)) if w is not None]
        if worlds and belief > 1:
            weights = self._bid_likelihood(worlds, seat, game_players, bidders, spil)
            worlds = self.rng.choices(worlds, weights, k=c.search_worlds)
        if not worlds:
            self.stats["no_world"] += 1
            return False
        order = [int(i) for i in np.argsort(-values, kind="stable")]
        chosen = [cands[i] for i in order[:c.search_k]]
        rest = [cands[i] for i in order[c.search_k:]]
        if c.search_random and rest:
            chosen += self.rng.sample(rest, min(c.search_random, len(rest)))
        if r.phase == BIDDING and getattr(c, "search_bid_lowest", 0):
            # pas and the next few steps up are always tried, whatever the net
            # thinks of them: a net that never bids never learns what a bid is
            # worth (Anders: "test alle ... se hvad der vinder og forstærk den gren")
            chosen += [a for a in explore_bids(cands, c.search_bid_lowest) if a not in chosen]
        before = expected_outcome(spil.totals, spil.left, c.runde_sd) if spil is not None else None
        job = _Job(game, seat, state, chosen, cands[order[0]], len(worlds), spil, before)
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
                    self.rollouts.append([job, (ci, wi), w, steps, next(steps)])
                except StopIteration:
                    self._result(job, (ci, wi), w, batch)
        self.stats["rollout_seconds"] += time.perf_counter() - t0
        return True

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
                        cands = F.candidates(step, actor)
                        if len(cands) > 1:
                            asks.append((i, F.to_bytes(F.encode(step, actor, 0, spil)), cands, action))
                    elif player.act(observe(step, actor)) != action:
                        mismatches[i] += 1
                step.apply(actor, action, check=False)
        if asks:
            q = self._score([(None, state, cands) for _, state, cands, _ in asks])
            start = 0
            for i, _, cands, action in asks:
                if cands[int(np.argmax(q[start:start + len(cands)]))] != action:
                    mismatches[i] += 1
                start += len(cands)
        self.stats["belief_mismatch"] = self.stats.get("belief_mismatch", 0) + sum(mismatches)
        return [miss ** m for m in mismatches]

    def _result(self, job, index, world, batch):
        c = self.config
        job.points[index] = _points(world, job.seat)
        job.q[index] = _q_target(world, job.seat, job.spil, job.before, c)
        job.pending -= 1
        if job.pending:
            return
        means = job.q.mean(axis=1)
        for action, points, mean in zip(job.cands, job.points.mean(axis=1), means):
            batch.add_search_row(job.state, action, float(points), float(mean), c.search_weight)
        best = int(np.argmax(means))
        net = job.cands.index(job.net_choice)
        diff = job.q[best] - job.q[net]  # paired: the same worlds
        se = diff.std(ddof=1) / np.sqrt(len(diff)) if len(diff) > 1 else 0.0
        if best != net and diff.mean() <= c.search_play_z * se:
            best = net  # not clearly better than the net's own choice: the max of noisy means flatters
        self.stats["changed"] += best != net
        self.stats["gain"] += float(means[best] - means[net])
        if c.search_explore and self.rng.random() < c.search_explore:
            best = self.rng.randrange(len(job.cands))
        batch.searched += 1
        job.game.parked = False
        self._advance(job.game, job.cands[best])


def _with(config, **changes):
    from dataclasses import replace
    return replace(config, **changes)


def play_searched(model, rng, config, partner, rules, batch, runder):
    """Sync mode (learner.sync_round): whole spil with search on the CPU,
    one at a time, until `runder` runder (at least one spil)."""
    while batch.runder < runder:
        games = SearchingGames(model, torch.device("cpu"), rng, config, partner, rules, refill=False, games=1)
        while not games.done():
            games.step(batch)


def policy_eval(model, config, deals=200, seed=3, device="cpu", bid_only=True):
    """Is the search's choice better than the net's? Same-hand duplicate
    at a Svær table: each deal is played once per seat with the net there
    (greedy), once without search and once searching every decision that
    search_share_bid covers (and, unless bid_only, every play decision).
    Returns the net's points per runde both ways and the paired
    difference (search - net) with a 95 % interval."""
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
    from .actor import Batch, rules_of
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
