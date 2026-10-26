"""The net's features (features.py) show a seat only what it may know, like
the observation (tests/test_observation.py):

- every card the features name is one the observation names (which is
  proven to be only cards the seat has seen);
- hidden-world swaps: deal the hidden cards differently and replay the same
  actions; the seat's features are identical in both worlds.
"""

import random
import unittest

from esmakker_ai import actions as A
from esmakker_ai import cards as C
from esmakker_ai import features as F
from esmakker_ai import meldinger as M
from esmakker_ai.engine import IllegalAction, Round
from esmakker_ai.observation import observe
from esmakker_ai.rules import Rules
from tests.test_observation import cards_named, hidden_variant, played_runder, snapshots

CARD_SEGMENTS = [F.HAND, *F.PLAYED, *F.TRICK, F.KITTY_KNOWN, F.LAID_AWAY, F.TURNED, F.FORDAEKT_FACE, F.OPEN_HAND]
FULL = (1 << 55) - 1


def cards_in_features(x):
    named = 0
    for offset in CARD_SEGMENTS:
        named |= (x >> offset) & FULL
    return set(C.cards_of(named))


class LayoutTest(unittest.TestCase):
    def test_sizes(self):
        self.assertEqual(0, F.STATE_BITS % 8)
        self.assertEqual(0, F.ACTION_BITS % 8)
        self.assertGreaterEqual(F.STATE_BITS, F.RULES + 8)
        r = Round(list(range(55)), 0)
        x = F.encode(r, 0)
        self.assertLess(x.bit_length(), F.STATE_BITS + 1)
        self.assertEqual(F.STATE_BYTES, len(F.to_bytes(x)))
        for action in range(F.ACTION_KINDS):
            bits = F.encode_action(action)
            self.assertLess(bits.bit_length(), F.ACTION_BITS + 1)
            self.assertTrue(bits >> action & 1)

    def test_bord_rules_are_input(self):
        self.assertLessEqual(sum(len(values) for _, values in F.RULE_FEATURES), 32)
        deal = list(range(55))
        seen = set()
        for rules in (Rules(), Rules(joker_trumpable=True), Rules(esmakker_banks_first=False),
                      Rules(pahaeng_order=("gode", "halve", "vip"))):
            seen.add((F.encode(Round(deal, 0, rules), 0) >> F.RULES) & ((1 << 32) - 1))
        self.assertEqual(4, len(seen))

    def test_own_hand_is_the_hand(self):
        rng = random.Random(3)
        for r in played_runder(30, seed=3):
            for step, seat, _ in snapshots(r):
                observer = rng.randrange(4)
                x = F.encode(step, observer)
                self.assertEqual(step.hand(observer), (x >> F.HAND) & FULL)

    def test_candidates_never_bank(self):
        for r in played_runder(200, seed=4):
            for step, seat, _ in snapshots(r):
                for s in range(4):
                    self.assertNotIn(A.BANK, F.candidates(step, s))


class NoLeakTest(unittest.TestCase):
    def test_features_name_only_cards_the_observation_names(self):
        checked = 0
        for r in played_runder(300, seed=21):
            for step, _, _ in snapshots(r):
                for observer in range(4):
                    leaked = cards_in_features(F.encode(step, observer)) - cards_named(observe(step, observer))
                    self.assertEqual(set(), leaked, f"seat {observer} at {step.tokens()!r}")
                    checked += 1
        self.assertGreater(checked, 30000)

    def test_a_seat_cannot_tell_hidden_worlds_apart(self):
        rng = random.Random(23)
        compared = esmakker_moved = kitty_moved = 0
        for r in played_runder(400, seed=23):
            if r.melder is None:
                continue
            for observer in range(4):
                variant = hidden_variant(r, observer, rng)
                one = Round(r.deal, r.dealer, r.rules)
                two = Round(variant, r.dealer, r.rules)
                for seat, action in r.log:
                    if r.kind == "stik" and M.pahaeng(r.melding) == M.HALVE and one.called_ace is not None:
                        break  # at halve the ace holder gives herself away to all
                    self.assertEqual(F.encode(one, observer), F.encode(two, observer),
                                     f"seat {observer} after {one.tokens()!r}")
                    if one.to_act() == observer:
                        self.assertEqual(F.candidates(one, observer), F.candidates(two, observer))
                    compared += 1
                    if one.called_ace is not None and one.esmakker != two.esmakker:
                        esmakker_moved += 1
                    if one.kitty_taken and set(one.kitty) != set(two.kitty):
                        kitty_moved += 1
                    one.apply(seat, action)
                    try:
                        two.apply(seat, action)
                    except IllegalAction:
                        break
        self.assertGreater(compared, 20000)
        self.assertGreater(esmakker_moved, 500)
        self.assertGreater(kitty_moved, 100)


if __name__ == "__main__":
    unittest.main()
