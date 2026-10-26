"""Bots that act on an observation (observation.py) only.

`act(obs)` returns an action (int, or a tuple of cards to lay away), or
None in the bank window for "no bank".
"""

import random

from . import actions as A
from . import meldinger as M

NINE = A.BID + M.stik(9)


class FirstBot:
    """The first es-makker bot (docs/bots/esmakker-strategy.md §2): melder 9
    if legal, otherwise pas; never goes with on sol (nor says "det kan jeg
    selv" or claims a jernhånd); never banks; every other choice (trump,
    called ace, vip turning, the kitty, fordækt, card) a random legal move
    from its own seeded RNG. Offered fordækt out of turn (selfplay.py) it
    lays one half the time."""

    def __init__(self, seed=None):
        self.rng = random.Random(seed)

    def act(self, obs):
        phase = obs["phase"]
        if phase == "bidding":
            return NINE if NINE in obs["legal_actions"] else A.PAS
        if phase == "banking":
            return None
        most = obs["discard_size"]
        if most:  # none up to `most` laid away, before the kitty is seen
            return tuple(self.rng.sample(obs["hand"], self.rng.randint(0, most)))
        return self.rng.choice(obs["legal_actions"])

    def offer_fordaekt(self, obs):
        """Fordækt out of turn (the melder is not forhånd; Ruby
        Bot#decide_out_of_turn): lay one or not with even odds, the card at
        random."""
        return self.rng.choice(obs["legal_actions"]) if self.rng.random() < 0.5 else None


class RandomBot:
    """Every choice a uniformly random legal one, banks included."""

    def __init__(self, seed=None):
        self.rng = random.Random(seed)

    def act(self, obs):
        most = obs["discard_size"]
        if most:  # none up to `most` laid away, before the kitty is seen
            return tuple(self.rng.sample(obs["hand"], self.rng.randint(0, most)))
        legal = obs["legal_actions"]
        if obs["phase"] == "banking":
            return A.BANK if A.BANK in legal and self.rng.random() < 0.5 else None
        return self.rng.choice(legal)

    def offer_fordaekt(self, obs):
        return self.rng.choice(obs["legal_actions"]) if self.rng.random() < 0.5 else None
