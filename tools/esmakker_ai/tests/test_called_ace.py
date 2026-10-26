"""The called ace is owed (Play#ace_owed, LegalMoves): the esmakker lays it
the first time its suit is led, and leads the suit only with it (Anders,
26 October 2026). The same cases as the Ruby AceJokersFordaektTest."""

import unittest

from esmakker_ai import actions as A
from esmakker_ai import cards as C
from esmakker_ai.engine import IllegalAction, Round

# Trump spades, the diamond ace called: seat 2 holds it, seat 3 is void in
# diamonds and holds spades, seat 0 has diamonds.
ACE_HANDS = {
    1: "2D AS KS QS AH KH QH JH AC KC QC JC TC".split(),
    2: "AD 3D X1 2H 3H 4H 5H 6H 7H 8H 9H TH 2C".split(),
    3: "2S 3S 4S 5S 6S 3C 4C 5C 6C 7C 8C 9C X2".split(),
}
ACE_KITTY = "9S TS JS".split()

# The melder (seat 1) has no diamonds; seat 2 holds the ace and 3D.
FORDAEKT_HANDS = {
    1: "AS KS QS AH KH QH JH AC KC QC JC TC 9C".split(),
    2: "AD 3D 2H 3H 4H 5H 6H 7H 8H 9H TH 5C 6C".split(),
    3: "4D 2S 3S 4S 5S 6S 7S 8S 9S TS 7C 8C X2".split(),
}


def deal_with(hands, kitty):
    placed = [C.parse(code) for codes in hands.values() for code in codes] + [C.parse(code) for code in kitty]
    rest = [card for card in range(55) if card not in placed]
    deal = []
    for seat in range(4):
        own = [C.parse(code) for code in hands.get(seat, [])]
        deal += own + [rest.pop(0) for _ in range(13 - len(own))]
    return deal + [C.parse(code) for code in kitty]


def run(round_, *steps):
    for seat, token in steps:
        round_.apply(seat, A.parse(token))
    return round_


def codes(cards):
    return sorted(C.code(card) for card in cards)


def ready(hands=ACE_HANDS, kitty=ACE_KITTY, melding="8"):
    """Seat 1 (forhånd) melder in spades, the diamond ace called, the
    cards dealt as `kitty` laid away, hands[1][10:] taken up from the
    kitty (she then holds hands[1])."""
    deal = deal_with({**hands, 1: hands[1][:10] + kitty}, hands[1][10:])
    r = Round(deal, dealer=0)
    return run(r, (1, melding), (2, "pas"), (3, "pas"), (0, "pas"), (1, "trumfS"), (1, "esD"),
               (1, "kast-" + "-".join(kitty)))


def esmakker_on_lead():
    """Seat 2 is forhånd and the esmakker; seat 3 the melder."""
    deal = deal_with({2: ACE_HANDS[2], 3: [c for c in ACE_HANDS[1] if c != "2D"] + ["2S"]}, ACE_KITTY)
    r = run(Round(deal, dealer=1), (2, "pas"), (3, "8"), (0, "pas"), (1, "pas"), (3, "trumfS"), (3, "esD"))
    hand = C.cards_of(r.hands[3])[:3]
    r.apply(3, tuple(hand))
    return r


class CalledAceTest(unittest.TestCase):
    def test_led_the_first_time_the_ace_is_the_only_card(self):
        r = run(ready(), (1, "2D"))
        self.assertEqual(["AD"], codes(r.legal_cards(2)))
        for code in ("3D", "X1", "2H"):
            with self.assertRaises(IllegalAction):
                r.clone().apply(2, A.PLAY + C.parse(code))
        run(r, (2, "AD"))
        self.assertEqual(sorted(ACE_HANDS[3]), codes(r.legal_cards(3)), "a seat void in the suit may trump the ace")

    def test_leading_she_leads_the_suit_only_with_the_ace(self):
        r = esmakker_on_lead()
        legal = codes(r.legal_cards(2))
        self.assertIn("AD", legal)
        self.assertNotIn("3D", legal)
        self.assertIn("X1", legal)
        self.assertIn("2H", legal)

    def test_a_led_joker_is_no_lead_in_the_suit(self):
        r = run(esmakker_on_lead(), (2, "X1"))
        for seat in (3, 0, 1):
            r.apply(seat, A.PLAY + r.legal_cards(seat)[0])
        self.assertEqual(2, r.to_act())
        self.assertNotIn("3D", codes(r.legal_cards(2)))

    def test_once_the_ace_has_been_played_as_a_discard_the_normal_rules(self):
        r = run(ready(), (1, "AS"), (2, "AD"), (3, "2S"))
        r.apply(0, A.PLAY + r.legal_cards(0)[0])
        run(r, (1, "2D"))
        self.assertEqual(["3D", "X1"], codes(r.legal_cards(2)))

    def test_the_fordaekt_card_led_is_the_suit_led(self):
        r = ready(hands=FORDAEKT_HANDS, kitty=["2C", "3C", "X3"])
        r.apply(1, A.FORDAEKT + C.parse("9C"))
        r.apply(1, A.PLAY + C.parse("9C"))
        self.assertEqual(["AD"], codes(r.legal_cards(2)))

    def test_at_halve_too(self):
        deal = deal_with(FORDAEKT_HANDS, ["2C", "3C", "X3"])
        r = run(Round(deal, dealer=0), (1, "8halve"), (2, "pas"), (3, "pas"), (0, "pas"), (1, "esD"), (2, "trumfS"),
                (2, "kast-5C-6C-2H"), (1, "fordaekt-9C"), (1, "9C"))
        self.assertEqual(["AD"], codes(r.legal_cards(2)))

    def test_nobody_else_owes_it_and_the_selvmakker_does_not(self):
        r = run(ready(), (1, "2D"))
        self.assertEqual([None, None, None], [r.ace_owed(seat) for seat in (0, 1, 3)])
        hands = {1: "2C 2H 3H 4H 5H 6H 7H 8H 9H TH JH QH KH".split()}
        deal = deal_with({1: hands[1]}, ["AD", "4D", "5D"])
        s = run(Round(deal, dealer=0), (1, "8"), (2, "pas"), (3, "pas"), (0, "pas"), (1, "trumfH"), (1, "esD"),
                (1, "kast-2C-2H-3H"))
        self.assertTrue(s.selvmakker())
        self.assertIsNone(s.ace_owed(1))


if __name__ == "__main__":
    unittest.main()
