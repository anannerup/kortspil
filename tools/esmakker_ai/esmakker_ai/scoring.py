"""How a runde is settled (Esmakker::Scoring), exactly, in Fractions.

Ruby returns whole amounts as integers and others as floats; here every
amount stays a Fraction (compare with Fraction(ruby_value)).
"""

from fractions import Fraction

from . import meldinger as M

SEATS = (0, 1, 2, 3)
NOTRUMP = 4


def doublings(melding, trump, points, vip_card=None, banks=0):
    p = M.pahaeng(melding)
    factor = Fraction(1)
    if p in (M.GODE, M.HALVE):
        factor *= points.pahaeng
    if p == M.VIP:
        if vip_card not in (1, 2, 3):
            raise ValueError(f"a vip melding is scored by its kitty card, 1-3: {vip_card!r}")
        factor *= (points.vip_first, points.vip_second, points.vip_third)[vip_card - 1]
    if trump == NOTRUMP:
        factor *= points.trumflos
    if p in (M.VIP, M.HALVE) and trump == 0:
        factor *= points.klor
    return factor * points.bank ** banks


def amount(melding, stik, trump, points, vip_card=None, banks=0):
    n = M.number(melding)
    stake = points.stake(n)
    factor = doublings(melding, trump, points, vip_card, banks)
    over = stik - n
    return stake * -over * factor if over < 0 else (stake + over) * factor


def stik_points(melding, side, stik, trump, points, vip_card=None, banks=0):
    """Points per seat of a played stik melding; side is the melder and the
    esmakker (or the selvmakker alone)."""
    others = [s for s in SEATS if s not in side]
    winners, losers = (side, others) if stik >= M.number(melding) else (others, side)
    per_pair = amount(melding, stik, trump, points, vip_card, banks)
    alone = winners if len(winners) == 1 else (losers if len(losers) == 1 else ())
    return [(1 if s in winners else -1) * per_pair * (3 if s in alone else 1) for s in SEATS]


def sol_points(players, vaeltet, value):
    """Each pair of seats settles once when their outcomes differ (klaret
    above not playing above væltet)."""
    def outcome(seat):
        if seat not in players:
            return 0
        return -1 if seat in vaeltet else 1

    totals = [Fraction(0)] * 4
    for a in range(4):
        for b in range(a + 1, 4):
            oa, ob = outcome(a), outcome(b)
            if oa == ob:
                continue
            winner, loser = (a, b) if oa > ob else (b, a)
            totals[winner] += value
            totals[loser] -= value
    return totals


def exact(value):
    """A number as Ruby's Scoring.exact (Rational(value.to_s)): the float
    0.1 is 1/10, not its binary value."""
    return Fraction(str(value)) if isinstance(value, float) else Fraction(value)


def total(points_per_runde):
    """Totals per seat of many runder's points (Fractions, or Ruby's ints
    and floats), summed exactly (Scoring.sum)."""
    totals = [Fraction(0)] * 4
    for points in points_per_runde:
        for seat in SEATS:
            totals[seat] += exact(points[seat])
    return totals
