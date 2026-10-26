"""The engine's own surface: cards, tokens, the ladder, legality, clone."""

import random
import unittest

from esmakker_ai import actions as A
from esmakker_ai import cards as C
from esmakker_ai import meldinger as M
from esmakker_ai.bots import RandomBot
from esmakker_ai.engine import IllegalAction, Round
from esmakker_ai.rules import Rules
from esmakker_ai.selfplay import play_runde, play_spil, random_deal


class CardsAndTokensTest(unittest.TestCase):
    def test_card_codes_round_trip(self):
        self.assertEqual(list(range(55)), [C.parse(C.code(card)) for card in range(55)])
        self.assertEqual(["2C", "AC", "2D", "AS", "X1", "X3"], [C.code(c) for c in (0, 12, 13, 51, 52, 54)])

    def test_action_tokens_round_trip(self):
        for action in range(A.ACTION_COUNT):
            self.assertEqual(action, A.parse(A.token(action)), A.token(action))
        self.assertEqual((0, 52, 25), A.parse("kast-2C-X1-AD"))
        self.assertEqual("trumfloes", A.token(A.TRUMP + A.NOTRUMP)[5:])

    def test_the_standard_ladder_is_anders_order(self):
        codes = [M.code(m) for m in M.ladder_for(("vip", "halve", "gode")).meldinger]
        self.assertEqual(["8", "8gode", "8halve", "8vip", "9", "9gode", "9halve", "9vip", "sol", "10"], codes[:10])
        self.assertEqual(["13", "13gode", "13halve", "13vip"], codes[-4:])
        self.assertEqual(28, len(codes))
        self.assertEqual(["8", "8halve", "8gode", "8vip"], [M.code(m) for m in M.ladder_for(("vip", "gode", "halve")).meldinger[:4]])


class RoundTest(unittest.TestCase):
    def setUp(self):
        self.round = Round(random_deal(random.Random(5)), dealer=3)

    def test_forhand_opens_and_illegal_actions_raise(self):
        self.assertEqual(0, self.round.to_act())
        with self.assertRaises(IllegalAction):
            self.round.apply(1, A.PAS)
        with self.assertRaises(IllegalAction):
            self.round.apply(0, A.SELV)
        self.round.apply(0, A.BID + M.stik(10))
        with self.assertRaises(IllegalAction):
            self.round.apply(1, A.BID + M.stik(9))

    def test_all_pass_is_a_redeal_by_the_former_forhand(self):
        for seat in (0, 1, 2, 3):
            self.round.apply(seat, A.PAS)
        self.assertTrue(self.round.redeal())
        self.assertEqual(0, self.round.next_dealer())
        self.assertEqual([], self.round.points())

    def test_clone_is_independent(self):
        bots = [RandomBot(seat) for seat in range(4)]
        self.round.apply(0, A.BID + M.stik(8))
        copy = self.round.clone()
        play_runde(copy, bots)
        self.assertTrue(copy.over())
        self.assertEqual(1, len(self.round.log))
        self.assertEqual("bidding", self.round.phase)
        self.assertEqual(Round.replay(copy.deal, copy.dealer, copy.log).tokens(), copy.tokens())

    def test_runder_sum_to_zero(self):
        rules = Rules.from_dict({"points": {"stakes": {"9": 1.25}, "bank": 2.5}})
        for seed in range(50):
            rounds, totals = play_spil([RandomBot(seed * 4 + seat) for seat in range(4)], runder=3, rules=rules, seed=seed)
            for r in rounds:
                if r.complete():
                    self.assertEqual(0, sum(r.points()))
            self.assertEqual(0, sum(totals))


if __name__ == "__main__":
    unittest.main()
