"""Scoring, with examples from the Ruby tests
(test/models/esmakker/scoring_test.rb, sol_scoring_test.rb)."""

import unittest
from fractions import Fraction

from esmakker_ai import meldinger as M
from esmakker_ai import scoring as S
from esmakker_ai.rules import Points, Rules

STANDARD = Points()
C, NOTRUMP = 0, 4


def points(melding, stik, trump=1, values=STANDARD, vip_card=None, banks=0, side=(1, 3)):
    return S.stik_points(melding, list(side), stik, trump, values, vip_card, banks)


class StikScoringTest(unittest.TestCase):
    def test_bet_and_hjem(self):
        self.assertEqual([1, -1, 1, -1], points(M.stik(8), 7))
        self.assertEqual([3, -3, 3, -3], points(M.stik(8), 5))
        self.assertEqual([-2, 2, -2, 2], points(M.stik(8, M.GODE), 8))
        self.assertEqual([-2, 2, -2, 2], points(M.stik(8), 8, trump=NOTRUMP))
        self.assertEqual([-10, 10, -10, 10], points(M.stik(9, M.HALVE), 10, trump=NOTRUMP))
        self.assertEqual([24, -24, 24, -24], points(M.stik(10, M.GODE), 7, trump=NOTRUMP))

    def test_vip_banks_and_klor(self):
        vip = M.stik(10, M.VIP)
        self.assertEqual([-4, 4, -4, 4], points(vip, 10, vip_card=1))
        self.assertEqual([-16, 16, -16, 16], points(vip, 10, vip_card=3))
        self.assertEqual([16, -16, 16, -16], points(vip, 9, vip_card=1, banks=2))
        self.assertEqual([-4, 4, -4, 4], points(M.stik(10), 10, banks=1))
        self.assertEqual([-16, 16, -16, 16], points(vip, 10, trump=C, vip_card=2))
        self.assertEqual([-32, 32, -32, 32], points(vip, 10, trump=NOTRUMP, vip_card=3))
        self.assertEqual([-8, 8, -8, 8], points(M.stik(10, M.HALVE), 10, trump=C))
        self.assertEqual([-2, 2, -2, 2], points(M.stik(10), 10, trump=C), "an ordinary melding: no klør doubling")
        self.assertEqual([-4, 4, -4, 4], points(M.stik(10, M.GODE), 10, trump=C), "gode: its påhæng only")
        with self.assertRaises(ValueError):
            points(vip, 10)

    def test_selvmakker_settles_with_each_of_the_three(self):
        self.assertEqual([-2.5, 7.5, -2.5, -2.5], points(M.stik(9), 10, side=(1,)))
        self.assertEqual([6, -18, 6, 6], points(M.stik(9, M.GODE), 7, side=(1,)))

    def test_the_bords_values_exactly(self):
        values = Points.from_dict({"stakes": {"8": 0.3}})
        self.assertEqual([Fraction(-3, 10), Fraction(3, 10), Fraction(-3, 10), Fraction(3, 10)],
                         points(M.stik(8), 8, values=values))
        self.assertEqual([Fraction(-3, 10), Fraction(3, 10), Fraction(-1, 10), Fraction(1, 10)],
                         S.total([[-0.1, 0.1, -0.1, 0.1], [-0.2, 0.2, 0, 0]]))

    def test_rules_read_rubys_hash(self):
        ruby = {"pahaeng_order": ["gode", "vip", "halve"], "joker_trumpable": True, "esmakker_banks_first": False,
                "bank_window": 5, "points": {"stakes": {"8": 0.5}, "bank": 3, "sol": 1.5}}
        rules = Rules.from_dict(ruby)
        self.assertEqual(("gode", "vip", "halve"), rules.pahaeng_order)
        self.assertEqual(Fraction(1, 2), rules.points.stake(8))
        self.assertEqual(Fraction(3, 2), rules.points.stake(9))
        self.assertEqual(Fraction(3, 2), rules.points.sol)
        self.assertEqual(rules, Rules.from_dict(rules.to_dict()))
        with self.assertRaises(ValueError):
            Rules.from_dict({"pahaeng_order": ["vip", "vip", "gode"]})


class SolScoringTest(unittest.TestCase):
    def test_each_pair_settles_once(self):
        # Bent (1) klarer sig, Carla (2) is væltet: Bent wins 3 × 3, Carla
        # loses 3 × 3, the two others lose once and win once.
        self.assertEqual([0, 9, -9, 0], S.sol_points((1, 2), [2], Fraction(3)))
        self.assertEqual([-3, 9, -3, -3], S.sol_points((1,), [], Fraction(3)))
        self.assertEqual([3, -9, 3, 3], S.sol_points((1,), [1], Fraction(3)))


if __name__ == "__main__":
    unittest.main()
