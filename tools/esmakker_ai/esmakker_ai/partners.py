"""The "human-like" partner bots of training (strategy §3: a share of the
games seats them on the three other seats, so the net learns to play with
a player who plays like a person).

A partner is made by `factory(seed)` and acts on observations
(observation.py), like the bots in bots.py. Svær (strategy §6) is the
partner the strategy asks for and the default; "first" is kept for
comparison. Another partner is one entry in PARTNERS.
"""

from .bots import FirstBot
from .svaer import Svaer


def _first(seed):
    return FirstBot(seed)


_SVAER = Svaer()  # deterministic and stateless: one serves every seat


def _svaer(seed):
    return _SVAER


PARTNERS = {"first": _first, "svaer": _svaer}


def factory(name):
    try:
        make = PARTNERS[name]
    except KeyError:
        raise ValueError(f"unknown partner {name!r}; one of {sorted(PARTNERS)}") from None
    make(0)  # fails now, not in an actor, when the partner does not exist yet
    return make
