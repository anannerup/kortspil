"""The spil around a runde (Anders: "et spil er 10 runder. det er ikke en
runde 10 gange. man akkumulerer point"): where a runde sits in its spil, who
wins a spil and by how much ("jo mere man vinder spillet med, jo større
belønning også", Anders), and what a runde did to each seat's expected
outcome of the spil.

A spil is `runder` played runder (REGLER §2.0, "Spillets længde"; a redeal
does not count); the points add up, and the highest total wins (ties split).
The standing is public: every seat sees the totals.
"""

import math
from collections import namedtuple

SPIL_RUNDER = 10  # the house standard (the rating plays spil of this many)


class SpilContext(namedtuple("SpilContext", "played runder totals")):
    """A runde's place in its spil: `played` runder already counted (0 for
    the first), of `runder`, and the totals so far per absolute seat."""

    __slots__ = ()

    @property
    def left(self):
        """Runder left, this one included."""
        return self.runder - self.played


START = SpilContext(0, SPIL_RUNDER, (0, 0, 0, 0))


def win_share(totals, seat):
    """The seat's share of the spil's win: 1 alone highest, 1/n in an n-way
    tie at the top, else 0."""
    best = max(totals)
    winners = sum(1 for t in totals if t == best)
    return 1 / winners if totals[seat] == best else 0.0


_DRAWS = {}


def _draws(count=1024, seed=12345):
    """Fixed standard normal draws for 4 seats, made zero-sum per draw and
    scaled to variance 1 per seat; closed under the four seat rotations, so
    equal totals give every seat exactly 1/4."""
    key = (count, seed)
    if key not in _DRAWS:
        import numpy as np
        z = np.random.default_rng(seed).standard_normal((count, 4))
        z = (z - z.mean(axis=1, keepdims=True)) / math.sqrt(0.75)
        _DRAWS[key] = np.concatenate([np.roll(z, k, axis=1) for k in range(4)])
    return _DRAWS[key]


def margin(totals, seat):
    """The seat's final total minus the best other seat's: above 0 a win by
    that much, below 0 a loss by that much (0: a tie at the top)."""
    return totals[seat] - max(totals[s] for s in range(4) if s != seat)


def outcome(totals):
    """Each seat's (margin, win share) at the end of a spil."""
    return [margin(totals, s) for s in range(4)], [win_share(totals, s) for s in range(4)]


def expected_outcome(totals, left, runde_sd):
    """Each seat's expected (margin, win share) at the end of the spil with
    `left` runder still to play from `totals`, if each future runde gives a
    seat zero-sum points with standard deviation `runde_sd` (independent
    runder; a Gaussian model, its spread measured once: Svær at all four
    seats, 4.7 points per runde). With no runder left it is the actual
    outcome."""
    if left <= 0:
        return outcome(totals)
    margins, wins = expected_outcomes([totals], left, runde_sd)
    return margins[0].tolist(), wins[0].tolist()


def expected_outcomes(totals, left, runde_sd):
    """expected_outcome for many spil at once: `totals` (n, 4), `left` > 0
    the same for all; numpy arrays (n, 4) of margins and win shares."""
    import numpy as np
    finals = np.asarray(totals, np.float64)[:, None, :] + _draws() * (runde_sd * math.sqrt(left))
    best = finals.max(axis=2, keepdims=True)
    top = finals == best
    wins = (top / top.sum(axis=2, keepdims=True)).mean(axis=1)
    # the best other seat: the second highest where the seat is the highest
    second = np.partition(finals, -2, axis=2)[:, :, -2:-1]
    margins = (finals - np.where(top, second, best)).mean(axis=1)
    return margins, wins
