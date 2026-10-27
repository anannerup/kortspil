"""Self-play: runder played with the net to make training samples, in the
learner's process (sync mode) or in actor processes, the net on the CPU one
decision at a time or on the GPU over many runder at once (actor_device, actor_games).
With actor_inference "server" the actors import no torch: one inference
process scores the decisions of all of them (inference.py).

A game is one spil: `runder` runder, the points adding up (spil.py). In a
share of them (partner_share) one seat is the net and the three others the
partner bot (partners.py) for the whole spil; only the net's seat gives
samples. Otherwise all four seats are the net and all give samples.
"""

import os
import queue as queue_module
import random
import signal

import numpy as np

from . import features as F
from .agent import ACTION_TABLE, NO_CONTRACT, NetPlayer, contract_label, play_steps, spil_targets, targets
from .engine import Round
from .inference import Stopped
from .partners import factory
from .rules import STANDARD
from .selfplay import random_deal
from .spil import SpilContext, expected_outcome, outcome


def rules_of(config):
    """Always the house rules (REGLER §2.0): bots play with them, so the net
    trains with them; nothing varies them."""
    return STANDARD


class Batch:
    """Samples gathered before they go to the learner: the runder's own
    rows, and search.py's rollout rows (weighted; Q only)."""

    def __init__(self):
        self.states = []
        self.actions = []
        self.targets = []
        self.runder = 0
        self.spil = 0
        self.search_rows = []  # (state bytes, action, target row, (q weight, other heads' weight))
        self.searched = 0
        self.counts = {}  # other counters for the learner's (search.py's melder check)

    def count(self, key, n):
        self.counts[key] = self.counts.get(key, 0) + n

    def __len__(self):
        return len(self.actions) + len(self.search_rows)

    def add_search_row(self, state, action, points, q, weight):
        """A searched candidate (search.py): its average runde points and Q
        target; only the Q loss uses it (weight), the other heads skip it."""
        self.search_rows.append((state, action, (points, 0.0, 0.0, 0.0, 0.0, 0.0, q, 0.0, *NO_CONTRACT),
                                 (weight, 0.0)))

    def add_contract_row(self, state, action, trump, side):
        """A rollout of a trump the melder may choose (search.py): the
        side's stik with it; only the contract head learns from it."""
        self.search_rows.append((state, action, (0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, float(trump), float(side)),
                                 (0.0, 0.0)))

    def arrays(self):
        """(states, actions, targets, weights): weights [n, 2] are the Q
        loss's and the other heads' (1, 1 for the runder's own rows)."""
        rows = self.search_rows
        all_states = self.states + [row[0] for row in rows]
        states = np.frombuffer(b"".join(all_states), np.uint8).reshape(len(all_states), F.STATE_BYTES)
        n = len(all_states)
        weights = np.ones((n, 2), np.float32)
        if rows:
            weights[len(self.actions):] = [row[3] for row in rows]
        return (states.copy(), np.array(self.actions + [row[1] for row in rows], np.int16),
                np.array(self.targets + [row[2] for row in rows], np.float32).reshape(n, -1), weights)


MAX_DEALS = 200  # a spil gives up after this many deals (redeals; as rating.py)


class LeaguePlayer(NetPlayer):
    """A seat played by an earlier snapshot of the run (config
    league_share): its decisions are scored by the inference server's
    league model `slot` (1 up to league_models), greedy. It gives no samples
    and the search leaves its decisions alone; inside the search's rollouts
    it is played by the current net, as every net seat is."""

    league = True

    def __init__(self, model, slot):
        super().__init__(model)
        self.slot = slot


def score_requests_of(scorer, requests):
    """scorer(states, cands) of play_steps requests (player, state, cands,
    ...); with league seats among them also each one's league model (slots;
    0 for the current net), so a scorer that knows no league is called as before."""
    states, cands = [req[1] for req in requests], [req[2] for req in requests]
    slots = [getattr(req[0], "slot", 0) for req in requests]
    return scorer(states, cands, slots) if any(slots) else scorer(states, cands)


def new_spil(model, rng, config, partner):
    """A spil of self-play set up: (players, the seats that give samples,
    whether all four seats are the net). The table is chosen per spil, as at
    a real bord: in a share of the spil (partner_share) one seat is the net
    and the three others the partner bot for the whole spil; in a share of
    the net-only spil (league_share, once the inference server holds earlier
    snapshots: model.league()) 1-3 seats are one earlier snapshot for the
    whole spil, so the net does not learn only how to beat itself."""
    net = NetPlayer(model, config.epsilon, rng, config.bid_epsilon)
    if rng.random() < config.partner_share:
        learner_seat = rng.randrange(4)
        players = [partner(rng.randrange(1 << 30)) for _ in range(4)]
        players[learner_seat] = net
        return players, (learner_seat,), False
    league = getattr(model, "league", None)
    share = getattr(config, "league_share", 0.0)
    if share and league is not None and rng.random() < share:
        models = league()
        if models:
            old = LeaguePlayer(model, rng.randrange(models) + 1)
            seats = rng.sample(range(4), rng.randint(1, 3))
            players = [old if s in seats else net for s in range(4)]
            return players, tuple(s for s in range(4) if s not in seats), True
    return [net] * 4, (0, 1, 2, 3), True


def runde_bidders(rng, config, partner, net_only):
    """The bidders of one runde, or None: in a share of a net-only spil's
    runder (bid_by_partner, chosen per runde: it is a curriculum for the
    meldingsrunde, not the table) the partner bot bids for every seat, so
    the net also learns to play the meldinger a human-like table ends on."""
    if net_only and config.bid_by_partner and rng.random() < config.bid_by_partner:
        return [partner(rng.randrange(1 << 30)) for _ in range(4)]
    return None


def spil_steps(model, rng, config, partner, rules):
    """One spil of self-play as a generator (like agent.play_steps: it
    yields each net decision to score and is sent the action). The kortgiver
    moves on and a redeal does not count, as in selfplay.play_spil; the
    points add up, and every decision sees the spil so far (SpilContext).
    Returns (samples [(state bytes, action, targets)], deals played); the
    targets are known only once the spil ends (agent.spil_targets)."""
    players, record, net_only = new_spil(model, rng, config, partner)
    dealer = rng.randrange(4)
    totals = [0.0] * 4
    played = deals = 0
    pending = []
    while played < config.runder and deals < MAX_DEALS:
        spil = SpilContext(played, config.runder, tuple(totals))
        r = Round(random_deal(rng), dealer, rules)
        bidders = runde_bidders(rng, config, partner, net_only)
        decisions = yield from play_steps(r, players, record, bidders=bidders, spil=spil)
        deals += 1
        before = expected_outcome(totals, config.runder - played, config.runde_sd)
        points = [0.0] * 4
        if r.complete():
            points = [float(p) for p in r.points()]
            totals = [t + p for t, p in zip(totals, points)]
            played += 1
        after = expected_outcome(totals, config.runder - played, config.runde_sd)
        for seat, chosen in decisions.items():
            if chosen:
                pending.append((seat, chosen, targets(r, seat) + contract_label(r, seat), points[seat], before, after))
        dealer = r.next_dealer()
    final = outcome(totals)
    samples = []
    for seat, chosen, row, points, before, after in pending:
        q = spil_targets(points, before, final if config.spil_target == "outcome" else after, seat, config)
        full = (*row[:-2], q, final[1][seat], *row[-2:])  # the contract label last (agent.TARGETS)
        samples.extend((state, action, full) for state, action in chosen)
    return samples, deals


def add_samples(done, batch):
    samples, deals = done
    for state, action, row in samples:
        batch.states.append(state)
        batch.actions.append(action)
        batch.targets.append(row)
    batch.runder += deals
    batch.spil += 1


def play_game(model, rng, config, partner, rules, batch):
    """One spil of self-play; its samples go into batch."""
    steps = spil_steps(model, rng, config, partner, rules)
    try:
        request = next(steps)
        while True:
            player, state, cands = request[:3]
            request = steps.send(cands[int(np.argmax(player.scores(state, cands)))])
    except StopIteration as done:
        add_samples(done.value, batch)


class LocalScorer:
    """Scores decisions with the model in this process (net.score_requests):
    scorer(states, cands) -> (every candidate's Q, each decision's best index)."""

    def __init__(self, model, device):
        import torch
        self.model, self.device = model, device
        self.actions = torch.from_numpy(ACTION_TABLE).to(device)

    def __call__(self, states, cands, slots=None):
        """`slots` (the league's models) are the inference server's: here
        every decision is the current net's (the league needs the server)."""
        from .net import score_requests
        return score_requests(self.model, self.actions, self.device, states, cands)


class NetStub:
    """What the players and the search read off the model when the net is
    in the inference process: no_sol, points_scale, and league(): how many
    earlier snapshots the server holds for league seats (0 without one)."""

    def __init__(self, no_sol, points_scale, league=None):
        self.no_sol, self.points_scale = bool(no_sol), float(points_scale)
        self._league = league  # a shared multiprocessing Value, or None

    def league(self):
        return int(self._league.value) if self._league is not None else 0


class BatchedGames:
    """config.actor_games spil played at once on one model (the GPU's):
    each step scores every spil's waiting decision in one forward pass,
    sends the actions, and replaces finished spil with new ones. `scorer`
    (default: LocalScorer(model, device)) scores them; model may then be a
    NetStub."""

    def __init__(self, model, device, rng, config, partner, rules, scorer=None):
        self.model, self.device, self.rng = model, device, rng
        self.config, self.partner, self.rules = config, partner, rules
        self.scorer = scorer if scorer is not None else LocalScorer(model, device)
        self.finished = []
        self.games = [self.start() for _ in range(max(1, config.actor_games))]

    def start(self):
        """[generator, its waiting request]; a spil with no net decision to
        score at all finishes inside (returned as None)."""
        steps = spil_steps(self.model, self.rng, self.config, self.partner, self.rules)
        try:
            return [steps, next(steps)]
        except StopIteration as done:
            self.finished.append(done.value)
            return None

    def step(self, batch):
        """One batched forward pass; finished spil's samples go into batch."""
        while None in self.games:
            self.games[self.games.index(None)] = self.start()
        cands = [g[1][2] for g in self.games]
        _, best = score_requests_of(self.scorer, [g[1] for g in self.games])
        for i, (game, c) in enumerate(zip(self.games, cands)):
            action = c[best[i]]
            try:
                game[1] = game[0].send(action)
            except StopIteration as done:
                self.finished.append(done.value)
                self.games[i] = None
        for done in self.finished:
            add_samples(done, batch)
        self.finished = []


GC_THRESHOLD = (10_000, 20, 100)  # Python's default is (2000, 10, 10)


def tune_gc():
    """Fewer garbage collections in a self-play process: the engine, Svær
    and the search make and drop millions of small objects, the memos and
    stik caches keep hundreds of thousands, and with Python's default
    thresholds a full collection walks all of them every few seconds (~5-10 %
    of an actor's time, measured). gc.freeze() leaves the objects of the
    imports (torch) out of every collection. Only how often unreachable
    cycles are freed changes, nothing that is played."""
    import gc
    gc.freeze()
    gc.set_threshold(*GC_THRESHOLD)


def lower_priority():
    """Below-normal CPU priority for this process and the ones it starts."""
    try:
        if os.name == "nt":
            import ctypes
            BELOW_NORMAL_PRIORITY_CLASS = 0x4000
            ctypes.windll.kernel32.SetPriorityClass(ctypes.windll.kernel32.GetCurrentProcess(),
                                                    BELOW_NORMAL_PRIORITY_CLASS)
        else:
            os.nice(10)
    except Exception:  # noqa: BLE001 - a priority we cannot set is no reason to stop
        pass


def _send(out_queue, stop_event, actor_id, batch):
    message = (actor_id, *batch.arrays(), batch.runder, batch.spil, batch.searched, batch.counts)
    while not stop_event.is_set():
        try:
            out_queue.put(message, timeout=0.5)
            return
        except queue_module.Full:
            continue


def group_seed(seed, group):
    """The rng seed of an actor's game group: group 0 plays as an actor
    without groups did."""
    return seed if group == 0 else hash((seed, group)) & 0x7FFFFFFF


def _group_loop(batched, out_queue, stop_event, actor_id, chunk):
    """A game group of an actor in its own thread (actor_groups): plays
    and sends its samples until the run stops."""
    batch = Batch()
    try:
        while not stop_event.is_set():
            batched.step(batch)
            if len(batch) >= chunk:
                _send(out_queue, stop_event, actor_id, batch)
                batch = Batch()
    except Stopped:
        pass


def actor_main(actor_id, config, shared_model, version, lock, out_queue, stop_event, seed, chunk=512, server=None):
    """An actor process: plays spil with its copy of the net and sends
    samples in chunks; copies the learner's weights when they change. With
    `server` (actor_inference "server": an inference.ClientSpec) it has no
    net and imports no torch: the inference process scores its decisions
    (shared_model is then the net's points_scale).

    `server` may be a list of ClientSpecs, one per game group (config
    actor_groups): each group plays its own spil with its own block at the
    server, group 0 in this thread and the others each in a thread of its
    own, so while one group waits for the server another plays on and the
    server gets more decisions per pass (the waits release the GIL)."""
    signal.signal(signal.SIGINT, signal.SIG_IGN)  # Ctrl+C is the learner's to handle
    out_queue.cancel_join_thread()
    if config.low_priority:
        lower_priority()
    rng = random.Random(seed)
    partner = factory(config.partner)
    rules = rules_of(config)
    batch = Batch()
    batched = None
    from .search import SearchingGames, enabled
    groups = list(server) if isinstance(server, (list, tuple)) else [server]
    if server is not None:
        server = groups[0]
    if len(groups) > 1:
        import threading
        from .inference import RemoteScorer
        stub = NetStub(config.no_sol, shared_model, getattr(groups[0], "league", None))
        for g, spec in enumerate(groups[1:], start=1):
            scorer = RemoteScorer(spec, stop_event)
            g_rng = random.Random(group_seed(seed, g))
            if enabled(config):
                other = SearchingGames(stub, None, g_rng, config, partner, rules, scorer=scorer,
                                       rollouts=scorer.rollouts)
            else:
                other = BatchedGames(stub, None, g_rng, config, partner, rules, scorer=scorer)
            threading.Thread(target=_group_loop, daemon=True,
                             args=(other, out_queue, stop_event, actor_id, chunk)).start()
    if server is not None:
        from .inference import RemoteScorer
        model, device = NetStub(config.no_sol, shared_model, getattr(server, "league", None)), None
        scorer = RemoteScorer(server, stop_event)
        shared_model = None
        gpu, rollouts = None, scorer.rollouts
    else:
        import torch
        from .net import build, pick_device
        torch.set_num_threads(1)
        device = pick_device(config.actor_device)
        model = build(config).to(device)
        model.eval()
        scorer = LocalScorer(model, device)
        gpu = rollouts = None
        if getattr(config, "search_gpu_rollouts", False):
            from .trollout import Rollouts
            gpu = Rollouts(model, device)
            rollouts = gpu.points_arrays
    seen = -1
    tune_gc()
    if enabled(config):
        batched = SearchingGames(model, device, rng, config, partner, rules, scorer=scorer, rollouts=rollouts)
    elif server is not None or device.type != "cpu" or config.actor_games > 1:
        batched = BatchedGames(model, device, rng, config, partner, rules, scorer=scorer)
    while not stop_event.is_set():
        if shared_model is not None and version.value != seen:
            with lock:
                seen = version.value
                model.load_state_dict(shared_model.state_dict())
                if gpu is not None:
                    gpu.refresh()
        if batched:
            try:
                batched.step(batch)
            except Stopped:  # the inference server stopped with the run
                return
        else:
            play_game(model, rng, config, partner, rules, batch)
        if len(batch) >= chunk:
            _send(out_queue, stop_event, actor_id, batch)
            batch = Batch()
