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
import time
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
    other total, its win share 1/k where it ties k-1 others at the top.

    Only the others' totals less the seat's own matter, and search's
    rollouts end on the same few standings again and again (points are
    whole numbers), so each standing is worked out once and kept (_SEAT)."""
    import numpy as np
    totals = np.asarray(totals, np.float64)
    others = [o for o in range(4) if o != seat]
    rel = totals[:, others] - totals[:, seat:seat + 1]
    unique, inverse = np.unique(rel, axis=0, return_inverse=True)
    get = _SEAT.entries.get
    keys = [(left, runde_sd, seat, *row) for row in unique.tolist()]
    found = [get(k) for k in keys]  # entry: [margin, win share, uses]
    missing = [i for i, e in enumerate(found) if e is None]
    if missing:
        _SEAT.prune()
        z = _scaled_draws(left, runde_sd)
        own = z[:, seat]
        finals = unique[missing][:, None, :] + z[:, others]
        best_other = finals.max(axis=2)
        ties = (finals == own[None, :, None]).sum(axis=2)
        wins = np.where(own >= best_other, 1.0 / (1 + ties), 0.0).mean(axis=1)
        margins = (own - best_other).mean(axis=1)
        entries = _SEAT.entries
        for i, m, w in zip(missing, margins.tolist(), wins.tolist()):
            found[i] = entries[keys[i]] = [m, w, 0]
    out = np.empty((len(found), 2))
    for i, e in enumerate(found):
        e[2] += 1
        out[i] = e[0], e[1]
    out = out[inverse.reshape(-1)]
    return out[:, 0], out[:, 1]


class _SeatMemo:
    """Memo of expected_seat_outcomes: (left, runde_sd, seat, the others'
    totals less the seat's) -> [expected margin, expected win share, uses].

    Every `every` seconds the standings used fewer than `min_hits` times
    since the last pruning go and the counts start over, so the standings a
    stretch of spil keeps using stay (Anders: count the uses, drop the rare
    ones after 10-15 minutes). The count lives in the entry, one add per
    use. Past `most` entries it prunes at once, and if that frees too
    little it starts over: a bound on RAM. Checked only when an entry is
    missing, so a call that finds everything costs no clock read."""

    def __init__(self, every=600, min_hits=2, most=300_000):
        self.every, self.min_hits, self.most = every, min_hits, most
        self.entries = {}
        self.pruned = time.monotonic()

    def prune(self):
        if time.monotonic() - self.pruned < self.every and len(self.entries) <= self.most:
            return
        kept = {k: e for k, e in self.entries.items() if e[2] >= self.min_hits}
        if len(kept) > self.most // 2:
            kept = {}
        for e in kept.values():
            e[2] = 0
        self.entries = kept
        self.pruned = time.monotonic()


_SEAT = _SeatMemo()
