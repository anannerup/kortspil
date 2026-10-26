"""Self-play: runder played with the net to make training samples, in the
learner's process (sync mode) or in actor processes, the net on the CPU one
decision at a time or on the GPU over many runder at once (actor_device, actor_games).

A game is one runde. In a share of them (partner_share) one seat is the net
and the three others the partner bot (partners.py); only the net's seat
gives samples. Otherwise all four seats are the net and all give samples.
"""

import os
import queue as queue_module
import random
import signal

import numpy as np
import torch

from . import features as F
from .agent import ACTION_TABLE, NetPlayer, play, play_steps, targets
from .engine import Round
from .net import build, pick_device, unpack
from .partners import factory
from .rules import STANDARD
from .selfplay import random_deal


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

    def __len__(self):
        return len(self.actions)

    def arrays(self):
        states = np.frombuffer(b"".join(self.states), np.uint8).reshape(len(self.states), F.STATE_BYTES)
        return (states.copy(), np.array(self.actions, np.int16),
                np.array(self.targets, np.float32).reshape(len(self.actions), -1))


def new_game(model, rng, config, partner, rules):
    """A runde of self-play set up: (round, players, the seats that give samples)."""
    r = Round(random_deal(rng), rng.randrange(4), rules)
    net = NetPlayer(model, config.epsilon, rng, config.bid_epsilon)
    if rng.random() < config.partner_share:
        learner_seat = rng.randrange(4)
        players = [partner(rng.randrange(1 << 30)) for _ in range(4)]
        players[learner_seat] = net
        return r, players, (learner_seat,)
    return r, [net] * 4, (0, 1, 2, 3)


def add_samples(r, decisions, batch):
    for seat, chosen in decisions.items():
        row = targets(r, seat)
        for state, action in chosen:
            batch.states.append(state)
            batch.actions.append(action)
            batch.targets.append(row)
    batch.runder += 1


def play_game(model, rng, config, partner, rules, batch):
    """One runde of self-play; its samples go into batch."""
    r, players, record = new_game(model, rng, config, partner, rules)
    add_samples(r, play(r, players, record), batch)


class BatchedGames:
    """config.actor_games runder played at once on one model (the GPU's):
    each step scores every runde's waiting decision in one forward pass,
    sends the actions, and replaces finished runder with new ones."""

    def __init__(self, model, device, rng, config, partner, rules):
        self.model, self.device, self.rng = model, device, rng
        self.config, self.partner, self.rules = config, partner, rules
        self.actions = torch.from_numpy(ACTION_TABLE).to(device)
        self.finished = []
        self.games = [self.start() for _ in range(max(1, config.actor_games))]

    def start(self):
        """(round, generator, its waiting request); runder with no net
        decision to score at all finish inside (returned as None)."""
        r, players, record = new_game(self.model, self.rng, self.config, self.partner, self.rules)
        steps = play_steps(r, players, record)
        try:
            return [r, steps, next(steps)]
        except StopIteration as done:
            self.finished.append((r, done.value))
            return None

    def step(self, batch):
        """One batched forward pass; finished runder's samples go into batch."""
        while None in self.games:
            self.games[self.games.index(None)] = self.start()
        states = np.frombuffer(b"".join(g[2][1] for g in self.games), np.uint8).reshape(len(self.games), -1)
        cands = [g[2][2] for g in self.games]
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
                game[2] = game[1].send(action)
            except StopIteration as done:
                self.finished.append((game[0], done.value))
                self.games[i] = None
        for r, decisions in self.finished:
            add_samples(r, decisions, batch)
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
    """An actor process: plays runder with its copy of the net and sends
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
            message = (actor_id, *batch.arrays(), batch.runder)
            batch = Batch()
            while not stop_event.is_set():
                try:
                    out_queue.put(message, timeout=0.5)
                    break
                except queue_module.Full:
                    continue
