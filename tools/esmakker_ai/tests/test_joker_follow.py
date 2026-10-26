"""A joker excuses nobody from following suit (Anders, 26 October 2026:
"man kan ikke smide en joker, hvis man kan bekende. Man SKAL bekende"):
a joker may always be led, and played into a stik led in a suit only by a
seat void in that suit; the same at the sol-meldinger. The same cases as
the Ruby PlayTest and SolPlayTest."""

import unittest

from esmakker_ai import actions as A
from esmakker_ai import cards as C
from esmakker_ai.engine import EXCHANGING, IllegalAction, PLAYING, Round

from tests.test_called_ace import codes, deal_with, esmakker_on_lead, ready, run

# Trump spades, the diamond ace called (test_called_ace's hands): seat 2
# holds hearts and X1, seat 3 is void in hearts and holds X2.


class JokerFollowTest(unittest.TestCase):
    def test_holding_a_joker_you_must_follow_suit(self):
        r = run(ready(), (1, "AH"))
        legal = codes(r.legal_cards(2))
        self.assertNotIn("X1", legal)
        self.assertEqual(["2H", "3H", "4H", "5H", "6H", "7H", "8H", "9H", "TH"], legal)
        with self.assertRaises(IllegalAction):
            r.clone().apply(2, A.PLAY + C.parse("X1"))

    def test_void_in_the_led_suit_a_joker_may_be_played(self):
        r = run(ready(), (1, "AH"), (2, "2H"))
        legal = codes(r.legal_cards(3))
        self.assertIn("X2", legal)
        self.assertEqual(codes(C.cards_of(r.hands[3])), legal, "void in hearts: anything")

    def test_a_joker_may_always_be_led(self):
        r = esmakker_on_lead()
        self.assertIn("X1", codes(r.legal_cards(2)))
        r = sol_round({1: "X1 AS KS QS AH KH QH JH AC KC QC JC TC".split()})
        self.assertEqual(codes(C.cards_of(r.hands[1])), codes(r.legal_cards(1)), "any card to lead, the joker too")

    def test_a_led_joker_leaves_no_suit_to_follow(self):
        hands = {1: "X1 AS KS QS AH KH QH JH AC KC QC JC TC".split(),
                 2: "2S 3S 2H 3H 4H 5H 6H 7H 8H 9H TH 2C X2".split()}
        r = sol_round(hands)
        run(r, (1, "X1"))
        self.assertEqual(codes(C.cards_of(r.hands[2])), codes(r.legal_cards(2)))

    def test_at_sol_too_a_joker_excuses_nobody_from_following(self):
        hands = {1: "3S 4H 5H 6H 7H 8H 9H TH JH QH KH AH 2C".split(),
                 2: "KS X2 2D 3D 4D 5D 6D 7D 8D 9D TD JD QD".split(),
                 3: "X3 2H 3C 4C 5C 6C 7C 8C 9C TC JC QC KC".split()}
        r = sol_round(hands)
        run(r, (1, "3S"))
        self.assertEqual(["KS"], codes(r.legal_cards(2)), "seat 2 holds spades: no joker")
        with self.assertRaises(IllegalAction):
            r.clone().apply(2, A.PLAY + C.parse("X2"))
        run(r, (2, "KS"))
        self.assertIn("X3", codes(r.legal_cards(3)), "seat 3 is void in spades")
        self.assertEqual(codes(C.cards_of(r.hands[3])), codes(r.legal_cards(3)))


def sol_round(hands, kitty=("4S", "5S", "6S")):
    """Seat 1 (forhånd) melder sol; nobody exchanges."""
    r = Round(deal_with(hands, list(kitty)), dealer=0)
    run(r, (1, "sol"), (2, "pas"), (3, "pas"), (0, "pas"))
    while r.phase == EXCHANGING:
        r.apply(r.to_act(), ())
    assert r.phase == PLAYING
    return r


if __name__ == "__main__":
    unittest.main()
