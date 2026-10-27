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
    key = (tuple(totals), left, runde_sd)
    out = _EXPECTED.get(key)
    if out is None:
        if len(_EXPECTED) > 20_000:
            _EXPECTED.clear()
        margins, wins = expected_outcomes([totals], left, runde_sd)
        out = _EXPECTED[key] = (tuple(margins[0].tolist()), tuple(wins[0].tolist()))
    return list(out[0]), list(out[1])


# Memo of expected_outcome: one runde's "after" is the next one's "before",
# and every search in a runde starts from the same standing.
_EXPECTED = {}


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


_SCALED = {}


def _scaled_draws(left, runde_sd):
    key = (left, runde_sd)
    z = _SCALED.get(key)
    if z is None:
        z = _SCALED[key] = _draws() * (runde_sd * math.sqrt(left))
    return z


def expected_seat_outcomes(totals, left, runde_sd, seat):
    """expected_outcomes for one seat only (search's Q targets): numpy
    arrays (n,) of its margins and win shares, the same numbers as
    expected_outcomes(...)[:, seat] up to float rounding, without the work
    for the other three seats. A seat's margin is its total less the best
    other total, its win share 1/k where it ties k-1 others at the top."""
    import numpy as np
    finals = np.asarray(totals, np.float64)[:, None, :] + _scaled_draws(left, runde_sd)
    own = finals[:, :, seat]
    others = finals[:, :, [o for o in range(4) if o != seat]]
    best_other = others.max(axis=2)
    ties = (others == own[:, :, None]).sum(axis=2)
    wins = np.where(own >= best_other, 1.0 / (1 + ties), 0.0).mean(axis=1)
    return (own - best_other).mean(axis=1), wins
