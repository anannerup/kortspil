"""Self-play: runder played with the net to make training samples, in the
learner's process (sync mode) or in actor processes on the CPU.

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
from .agent import NetPlayer, play, targets
from .engine import Round
from .net import build
from .partners import factory
from .rules import STANDARD, Rules
from .selfplay import random_deal


def rules_of(config):
    return Rules.from_dict(config.rules) if config.rules else STANDARD


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


def play_game(model, rng, config, partner, rules, batch):
    """One runde of self-play; its samples go into batch."""
    r = Round(random_deal(rng), rng.randrange(4), rules)
    net = NetPlayer(model, config.epsilon, rng, config.bid_epsilon)
    if rng.random() < config.partner_share:
        learner_seat = rng.randrange(4)
        players = [partner(rng.randrange(1 << 30)) for _ in range(4)]
        players[learner_seat] = net
        record = (learner_seat,)
    else:
        players = [net] * 4
        record = (0, 1, 2, 3)
    decisions = play(r, players, record)
    for seat, chosen in decisions.items():
        row = targets(r, seat)
        for state, action in chosen:
            batch.states.append(state)
            batch.actions.append(action)
            batch.targets.append(row)
    batch.runder += 1


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
    model = build(config)
    model.eval()
    seen = -1
    partner = factory(config.partner)
    rules = rules_of(config)
    batch = Batch()
    while not stop_event.is_set():
        if version.value != seen:
            with lock:
                seen = version.value
                model.load_state_dict(shared_model.state_dict())
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
