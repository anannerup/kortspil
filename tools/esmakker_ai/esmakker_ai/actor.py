"""Self-play: runder played with the net to make training samples, in the
learner's process (sync mode) or in actor processes, the net on the CPU one
decision at a time or on the GPU over many runder at once (actor_device, actor_games).

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
import torch

from . import features as F
from .agent import ACTION_TABLE, NetPlayer, play_steps, spil_targets, targets
from .engine import Round
from .net import build, pick_device, unpack
from .partners import factory
from .rules import STANDARD
from .selfplay import random_deal
from .spil import SpilContext, expected_outcome, outcome


def rules_of(config):
    """Always the house rules (REGLER §2.0): bots play with them, so the net
    trains with them; nothing varies them."""
    return STANDARD


class Batch:
    """Samples gathered before they go to the learner."""

    def __init__(self):
        self.states = []
        self.actions = []
        self.targets = []
        self.runder = 0
        self.spil = 0

    def __len__(self):
        return len(self.actions)

    def arrays(self):
        states = np.frombuffer(b"".join(self.states), np.uint8).reshape(len(self.states), F.STATE_BYTES)
        return (states.copy(), np.array(self.actions, np.int16),
                np.array(self.targets, np.float32).reshape(len(self.actions), -1))


MAX_DEALS = 200  # a spil gives up after this many deals (redeals; as rating.py)


def new_spil(model, rng, config, partner):
    """A spil of self-play set up: (players, the seats that give samples,
    whether all four seats are the net). The table is chosen per spil, as at
    a real bord: in a share of the spil (partner_share) one seat is the net
    and the three others the partner bot for the whole spil."""
    net = NetPlayer(model, config.epsilon, rng, config.bid_epsilon)
    if rng.random() < config.partner_share:
        learner_seat = rng.randrange(4)
        players = [partner(rng.randrange(1 << 30)) for _ in range(4)]
        players[learner_seat] = net
        return players, (learner_seat,), False
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
                pending.append((seat, chosen, targets(r, seat), points[seat], before, after))
        dealer = r.next_dealer()
    final = outcome(totals)
    samples = []
    for seat, chosen, row, points, before, after in pending:
        q = spil_targets(points, before, final if config.spil_target == "outcome" else after, seat, config)
        full = (*row, q, final[1][seat])
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
            player, state, cands = request
            request = steps.send(cands[int(np.argmax(player.scores(state, cands)))])
    except StopIteration as done:
        add_samples(done.value, batch)


class BatchedGames:
    """config.actor_games spil played at once on one model (the GPU's):
    each step scores every spil's waiting decision in one forward pass,
    sends the actions, and replaces finished spil with new ones."""

    def __init__(self, model, device, rng, config, partner, rules):
        self.model, self.device, self.rng = model, device, rng
        self.config, self.partner, self.rules = config, partner, rules
        self.actions = torch.from_numpy(ACTION_TABLE).to(device)
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
        states = np.frombuffer(b"".join(g[1][1] for g in self.games), np.uint8).reshape(len(self.games), -1)
        cands = [g[1][2] for g in self.games]
        counts = torch.tensor([len(c) for c in cands], device=self.device)
        with torch.inference_mode():
            s = torch.from_numpy(unpack(states)).to(self.device, non_blocking=True)
            h = self.model.encode_state(s).repeat_interleave(counts, dim=0)
            a = self.actions[torch.tensor([x for c in cands for x in c], device=self.device)]
            q = self.model.q_values(h, a).cpu().numpy()
        start = 0
        for i, (game, c) in enumerate(zip(self.games, cands)):
            action = c[int(np.argmax(q[start:start + len(c)]))]
            start += len(c)
            try:
                game[1] = game[0].send(action)
            except StopIteration as done:
                self.finished.append(done.value)
                self.games[i] = None
        for done in self.finished:
            add_samples(done, batch)
        self.finished = []


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


def actor_main(actor_id, config, shared_model, version, lock, out_queue, stop_event, seed, chunk=512):
    """An actor process: plays spil with its copy of the net and sends
    samples in chunks; copies the learner's weights when they change."""
    signal.signal(signal.SIGINT, signal.SIG_IGN)  # Ctrl+C is the learner's to handle
    out_queue.cancel_join_thread()
    if config.low_priority:
        lower_priority()
    torch.set_num_threads(1)
    rng = random.Random(seed)
    device = pick_device(config.actor_device)
    model = build(config).to(device)
    model.eval()
    seen = -1
    partner = factory(config.partner)
    rules = rules_of(config)
    batch = Batch()
    batched = None
    if device.type != "cpu" or config.actor_games > 1:
        batched = BatchedGames(model, device, rng, config, partner, rules)
    while not stop_event.is_set():
        if version.value != seen:
            with lock:
                seen = version.value
                model.load_state_dict(shared_model.state_dict())
        if batched:
            batched.step(batch)
        else:
            play_game(model, rng, config, partner, rules, batch)
        if len(batch) >= chunk:
            message = (actor_id, *batch.arrays(), batch.runder, batch.spil)
            batch = Batch()
            while not stop_event.is_set():
                try:
                    out_queue.put(message, timeout=0.5)
                    break
                except queue_module.Full:
                    continue
