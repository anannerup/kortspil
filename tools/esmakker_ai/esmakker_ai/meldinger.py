"""Meldinger as small ints and the bord's ladder (Esmakker::Melding, Ladder).

A stik melding is (number - 8) * 4 + påhæng, påhæng 0 none, 1 gode,
2 halve, 3 vip: ids 0-23. The sol-meldinger are 24-27.
"""

PAHAENG = ("gode", "halve", "vip")  # påhæng index 1, 2, 3
NONE, GODE, HALVE, VIP = 0, 1, 2, 3
NUMBERS = range(8, 14)
SOL, REN_SOL, BORDLAEGGER, REN_BORDLAEGGER = 24, 25, 26, 27
SOL_KINDS = ("sol", "ren_sol", "bordlaegger", "ren_bordlaegger")
COUNT = 28
# The most stik a sol player may take (SolPlay::MOST_STIK).
MOST_STIK = {SOL: 1, REN_SOL: 0, BORDLAEGGER: 1, REN_BORDLAEGGER: 0}
OPEN_HAND = (BORDLAEGGER, REN_BORDLAEGGER)
SOL_AFTER = {9: SOL, 10: REN_SOL, 11: BORDLAEGGER, 12: REN_BORDLAEGGER}


def stik(number, pahaeng=NONE):
    return (number - 8) * 4 + pahaeng


def is_sol(melding):
    return melding >= SOL


def number(melding):
    return melding // 4 + 8


def pahaeng(melding):
    """0 none, 1 gode, 2 halve, 3 vip; -1 for a sol-melding."""
    return -1 if melding >= SOL else melding % 4


def code(melding):
    if melding >= SOL:
        return SOL_KINDS[melding - SOL]
    p = melding % 4
    return f"{melding // 4 + 8}{PAHAENG[p - 1] if p else ''}"


CODES = tuple(code(m) for m in range(COUNT))
IDS = {c: m for m, c in enumerate(CODES)}


def parse(text):
    try:
        return IDS[text]
    except KeyError:
        raise ValueError(f"not a melding: {text!r}") from None


class Ladder:
    """The one ranked list of meldinger, lowest first, for a påhæng order
    given highest first ("vip", "halve", "gode")."""

    __slots__ = ("pahaeng_order", "meldinger", "ranks")

    def __init__(self, pahaeng_order=("vip", "halve", "gode")):
        order = tuple(str(p) for p in pahaeng_order)
        if any(p not in PAHAENG for p in order) or len(set(order)) != len(order):
            raise ValueError(f"bad påhæng order {pahaeng_order!r}")
        self.pahaeng_order = order
        meldinger = []
        for n in NUMBERS:
            meldinger.append(stik(n))
            meldinger.extend(stik(n, PAHAENG.index(p) + 1) for p in reversed(order))
            if n in SOL_AFTER:
                meldinger.append(SOL_AFTER[n])
        self.meldinger = tuple(meldinger)
        ranks = [-1] * COUNT
        for i, m in enumerate(meldinger):
            ranks[m] = i
        self.ranks = tuple(ranks)

    def includes(self, melding):
        return 0 <= melding < COUNT and self.ranks[melding] >= 0

    def above(self, melding):
        """Every melding strictly above (all for None), lowest first."""
        if melding is None:
            return self.meldinger
        return self.meldinger[self.ranks[melding] + 1:]


_LADDERS = {}


def ladder_for(pahaeng_order):
    key = tuple(pahaeng_order)
    ladder = _LADDERS.get(key)
    if ladder is None:
        ladder = _LADDERS[key] = Ladder(key)
    return ladder
