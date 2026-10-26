"""The bord's rules and point values (Esmakker::Rules, Points).

Amounts are exact Fractions, read as Ruby reads them (Rational(value.to_s)):
1.5 is 3/2. Rules.from_dict reads Ruby's Rules#to_h (e.g. from JSON).
"""

from dataclasses import dataclass, field
from fractions import Fraction

PAHAENG_ORDER = ("vip", "halve", "gode")
NUMBERS = ("8", "9", "10", "11", "12", "13")
STANDARD_STAKES = {"8": 1, "9": 1.5, "10": 2, "11": 2.5, "12": 3, "13": 3.5}
FACTORS = ("pahaeng", "trumflos", "klor", "vip_first", "vip_second", "vip_third", "bank")
AMOUNTS = ("sol", "ren_sol", "bordlaegger", "ren_bordlaegger")
STANDARD_VALUES = {"pahaeng": 2, "trumflos": 2, "klor": 2, "vip_first": 2, "vip_second": 4, "vip_third": 8, "bank": 2,
                   "sol": 3, "ren_sol": 4, "bordlaegger": 5, "ren_bordlaegger": 6}


def exact(value):
    """An amount as Ruby's Scoring.exact: Rational(value.to_s)."""
    if isinstance(value, Fraction):
        return value
    if isinstance(value, bool) or not isinstance(value, (int, float, str)):
        raise ValueError(f"an amount is a number, not {value!r}")
    result = Fraction(str(value))
    if result <= 0:
        raise ValueError(f"an amount is positive, not {value!r}")
    return result


@dataclass(frozen=True)
class Points:
    stakes: dict = field(default_factory=lambda: {n: exact(v) for n, v in STANDARD_STAKES.items()})
    pahaeng: Fraction = Fraction(2)
    trumflos: Fraction = Fraction(2)
    klor: Fraction = Fraction(2)
    vip_first: Fraction = Fraction(2)
    vip_second: Fraction = Fraction(4)
    vip_third: Fraction = Fraction(8)
    bank: Fraction = Fraction(2)
    sol: Fraction = Fraction(3)
    ren_sol: Fraction = Fraction(4)
    bordlaegger: Fraction = Fraction(5)
    ren_bordlaegger: Fraction = Fraction(6)

    @classmethod
    def from_dict(cls, values):
        values = dict(values or {})
        unknown = set(values) - set(FACTORS) - set(AMOUNTS) - {"stakes"}
        if unknown:
            raise ValueError(f"unknown point keys {sorted(unknown)}")
        stakes = dict(STANDARD_STAKES)
        stakes.update({str(k): v for k, v in (values.pop("stakes", None) or {}).items()})
        if sorted(stakes) != sorted(NUMBERS):
            raise ValueError("stakes are one per number 8-13")
        merged = {k: exact(values.get(k, STANDARD_VALUES[k])) for k in (*FACTORS, *AMOUNTS)}
        return cls(stakes={n: exact(stakes[n]) for n in NUMBERS}, **merged)

    def to_dict(self):
        def plain(v):
            return int(v) if v.denominator == 1 else float(v)
        out = {"stakes": {n: plain(self.stakes[n]) for n in NUMBERS}}
        out.update({k: plain(getattr(self, k)) for k in (*FACTORS, *AMOUNTS)})
        return out

    def stake(self, number):
        return self.stakes[str(number)]

    def sol_amount(self, kind):
        return getattr(self, kind)


@dataclass(frozen=True)
class Rules:
    pahaeng_order: tuple = PAHAENG_ORDER
    joker_trumpable: bool = False
    esmakker_banks_first: bool = True
    bank_window: int = 8
    points: Points = field(default_factory=Points)

    def __post_init__(self):
        order = tuple(str(p) for p in self.pahaeng_order)
        if sorted(order) != sorted(PAHAENG_ORDER):
            raise ValueError("the påhæng order holds vip, halve, gode once each")
        object.__setattr__(self, "pahaeng_order", order)
        if not isinstance(self.joker_trumpable, bool) or not isinstance(self.esmakker_banks_first, bool):
            raise ValueError("rule toggles must be true or false")
        if not isinstance(self.bank_window, int) or not 5 <= self.bank_window <= 10:
            raise ValueError("the bank window is 5-10 seconds")

    @classmethod
    def from_dict(cls, values):
        values = dict(values or {})
        unknown = set(values) - {"pahaeng_order", "joker_trumpable", "esmakker_banks_first", "bank_window", "points"}
        if unknown:
            raise ValueError(f"unknown rule keys {sorted(unknown)}")
        if "points" in values and not isinstance(values["points"], Points):
            values["points"] = Points.from_dict(values["points"])
        if "pahaeng_order" in values:
            values["pahaeng_order"] = tuple(values["pahaeng_order"])
        return cls(**values)

    def to_dict(self):
        return {"pahaeng_order": list(self.pahaeng_order), "joker_trumpable": self.joker_trumpable,
                "esmakker_banks_first": self.esmakker_banks_first, "bank_window": self.bank_window,
                "points": self.points.to_dict()}


STANDARD = Rules()
