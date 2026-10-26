"""The "human-like" partner bots of training (strategy §3: a share of the
games seats them on the three other seats, so the net learns to play with
a player who plays like a person).

A partner is made by `factory(seed)` and acts on observations
(observation.py), like the bots in bots.py. Svær (strategy §6) is the
partner the strategy asks for; until it is built, training uses FirstBot.

Hook for Svær: write `SvaerBot` (in bots.py or its own module), then
replace `_svaer` below with `return SvaerBot(seed)` and start (or resume)
a run with `--set partner=svaer`.
"""

from .bots import FirstBot


def _first(seed):
    return FirstBot(seed)


def _svaer(seed):
    raise NotImplementedError("Svær (strategy §6) is not built yet: write it, then register it in partners.py")


PARTNERS = {"first": _first, "svaer": _svaer}


def factory(name):
    try:
        make = PARTNERS[name]
    except KeyError:
        raise ValueError(f"unknown partner {name!r}; one of {sorted(PARTNERS)}") from None
    make(0)  # fails now, not in an actor, when the partner does not exist yet
    return make
