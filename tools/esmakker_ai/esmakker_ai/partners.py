"""The "human-like" partner bots of training (strategy §3: a share of the
games seats them on the three other seats, so the net learns to play with
a player who plays like a person).

A partner is made by `factory(seed)` and acts on observations
(observation.py), like the bots in bots.py. Svær (strategy §6) is the
partner the strategy asks for and the default; "first" is kept for
comparison. Another partner is one entry in PARTNERS.
"""

import random

from .bots import FirstBot
from .svaer import Svaer


def _first(seed):
    return FirstBot(seed)


_SVAER = Svaer()  # deterministic and stateless: one serves every seat


def _svaer(seed):
    return _SVAER


def _mix(seed):
    """Svær at most seats, the first bot (melder 9 on everything) at about
    one in four: the net also meets a table that overbids, and learns to
    punish it (the rating's field is three first bots)."""
    return FirstBot(seed) if random.Random(seed).random() < 0.25 else _SVAER


PARTNERS = {"first": _first, "svaer": _svaer, "mix": _mix}


def factory(name):
    try:
        make = PARTNERS[name]
    except KeyError:
        raise ValueError(f"unknown partner {name!r}; one of {sorted(PARTNERS)}") from None
    make(0)  # fails now, not in an actor, when the partner does not exist yet
    return make
