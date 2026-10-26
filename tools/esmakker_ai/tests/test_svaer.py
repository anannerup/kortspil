"""Svær (strategy §6), the same cases as Ruby's test/models/esmakker/svaer_test.rb,
and parity with the Ruby Svær on the committed sample."""

import random
import unittest
from pathlib import Path

from esmakker_ai import actions as A
from esmakker_ai import cards as C
from esmakker_ai import meldinger as M
from esmakker_ai import svaer as S
from esmakker_ai.bots import FirstBot
from esmakker_ai.engine import BANKING, Round
from esmakker_ai.observation import observe
from esmakker_ai.rules import Rules
from esmakker_ai.selfplay import random_deal
from esmakker_ai.svaer_parity import run

STRONG = "AS KS QS JS 9S 8S AH KH AD QD KC QC X1".split()
MEDIUM = "AS KS QS 7S 5S AH 4H 3H AD 5D 4C 3C 2C".split()
WEAK = "2C 3C 4C 5C 2D 3D 4D 5D 2H 3H 4H 6S 7S".split()
SAMPLE = Path(__file__).parent / "fixtures" / "svaer_parity_sample.jsonl.gz"


def ints(codes):
    return sorted(C.parse(code) for code in codes)


def round_with(hands, rules=Rules()):
    placed = [C.parse(code) for codes in hands.values() for code in codes]
    rest = [card for card in range(55) if card not in placed]
    deal = []
    for seat in range(4):
        own = [C.parse(code) for code in hands.get(seat, [])]
        deal.extend(own + [rest.pop(0) for _ in range(13 - len(own))])
    deal.extend(rest[:3])
    return Round(deal, 0, rules)


def knowledge(hand, trump, seat=0, melder=1, esmakker=None, called=0, trick=(), tricks=(), rules=Rules()):
    trick = list(trick)
    led = None if not trick or trick[0][1] >= 52 else trick[0][1] // 13
    following = [c for c in hand if led is not None and c < 52 and c // 13 == led]
    k = S.Knowledge()
    values = dict(seat=seat, phase="playing", hand=hand, rules=rules, melding=M.stik(9), bids=[], can_selv=False,
                  can_med=False, can_pas=False, trumps=[], aces=[], can_turn=False, can_accept=False, kind="stik",
                  melder=melder, trump=trump, called=called, esmakker=esmakker, selvmakker=False, turned=[],
                  vip_card=None, banks=0, discard_size=0, discarded=[], fordaekt_card=None, fordaekt_waiting=False,
                  fordaekt_options=[], tricks=list(tricks), trick=trick, tricks_won=[0, 0, 0, 0],
                  legal=following or hand, kitty_cards=[], players=[], most_stik=None, vaeltet=[], open_hand=None)
    for name, value in values.items():
        setattr(k, name, value)
    return k


def decide(r, seat):
    return S.Svaer().decide(observe(r, seat))


class HandTest(unittest.TestCase):
    def test_estimates(self):
        values = S.estimates(ints(STRONG))
        self.assertEqual(14, values[3])
        self.assertEqual(13, S.nmax(max(values)))
        self.assertEqual(8, S.nmax(max(S.estimates(ints(MEDIUM)))))
        self.assertIsNone(S.nmax(max(S.estimates(ints(WEAK)))))

    def test_meldingsrunde(self):
        action, thought = decide(round_with({1: STRONG}), 1)
        self.assertEqual((A.BID + M.parse("8vip"), "bid_vip"), (action, thought["reason"]))
        self.assertEqual({"self": 12, "makker": 2}, thought["expect"]["stik"])
        action, thought = decide(round_with({1: MEDIUM}), 1)
        self.assertEqual((A.BID + M.stik(8), "bid_lowest", 1.25), (action, thought["reason"], thought["expect"]["points"]))
        self.assertEqual((A.PAS, "pas_weak"), (decide(round_with({1: WEAK}), 1)[0], decide(round_with({1: WEAK}), 1)[1]["reason"]))
        r = round_with({2: MEDIUM})
        r.apply(1, A.BID + M.stik(9))
        action, thought = decide(r, 2)
        self.assertEqual((A.PAS, "pas_too_high"), (action, thought["reason"]))


class PlayTest(unittest.TestCase):
    def test_afkast_renonce(self):
        k = knowledge(ints("5S 6S AH 4H 3D 7D 9D".split()), 3, trick=[(0, C.parse("KC"))])
        self.assertEqual((C.parse("3D"), "afkast_renonce"), S.follow(k, S.Table(k, S.PARAMS), S.PARAMS))

    def test_afkast_spil_den_her(self):
        k = knowledge(ints("5S 6S AH 4H 3D 7D 9D".split()), 3, trick=[(0, C.parse("KC"))], rules=Rules(afkast="spil_den_her"))
        self.assertEqual((C.parse("4H"), "afkast_spil"), S.follow(k, S.Table(k, S.PARAMS), S.PARAMS))

    def test_reads_makkers_discard(self):
        stik = (3, [(3, C.parse("2C")), (0, C.parse("5C")), (1, C.parse("3D")), (2, C.parse("4C"))], 3)
        hand = ints("6D 8D 9H TH 2S".split())
        spil = knowledge(hand, 0, seat=3, melder=1, esmakker=3, called=2, tricks=[stik], rules=Rules(afkast="spil_den_her"))
        renonce = knowledge(hand, 0, seat=3, melder=1, esmakker=3, called=2, tricks=[stik])
        self.assertEqual((C.parse("6D"), "signal_suit"), S.lead(spil, S.Table(spil, S.PARAMS), S.PARAMS))
        self.assertNotEqual("signal_suit", S.lead(renonce, S.Table(renonce, S.PARAMS), S.PARAMS)[1])

    def test_good_trumps_draw_weak_trumps_play_makker_in(self):
        good = knowledge(ints("AS KS QS 9S 7S 4H 3D 5D 7D 2C 3C 4C 5C".split()), 3, seat=1, called=2)
        weak = knowledge(ints("9S 7S 5S 4S 3S 4H AD 5D 7D 2C 3C 4C 5C".split()), 3, seat=1, called=2)
        self.assertEqual((C.parse("AS"), "draw_trump"), S.lead(good, S.Table(good, S.PARAMS), S.PARAMS))
        self.assertEqual((C.parse("4H"), "makker_in"), S.lead(weak, S.Table(weak, S.PARAMS), S.PARAMS))

    def test_esmakker_lays_the_ace(self):
        k = knowledge(ints("AH 4H 3D".split()), 3, seat=2, esmakker=2, called=2, trick=[(1, C.parse("5H"))])
        self.assertEqual((C.parse("AH"), "lay_ace"), S.follow(k, S.Table(k, S.PARAMS), S.PARAMS))


class GamesTest(unittest.TestCase):
    def test_never_banks_and_only_legal_moves(self):
        rng = random.Random(3)
        for index in range(300):
            rules = Rules(afkast=("renonce", "spil_den_her")[index % 2], joker_trumpable=index % 3 == 0)
            svaer = [0, 1, 2, 3] if index % 2 == 0 else [index % 4]
            bots = [S.Svaer() if seat in svaer else FirstBot(index * 4 + seat) for seat in range(4)]
            r = Round(random_deal(rng), index % 4, rules)
            while not r.over():
                if r.phase == BANKING:
                    for seat in range(4):
                        self.assertIsNone(S.Svaer().act(observe(r, seat)))
                    r.apply(r.melder, A.BANKSLUT)
                    continue
                seat = r.to_act()
                r.apply(seat, bots[seat].act(observe(r, seat)))  # raises IllegalAction on an illegal move

    def test_never_banks_in_the_bank_window(self):
        r = round_with({1: STRONG})
        for seat, action in ((1, A.BID + M.parse("8vip")), (2, A.PAS), (3, A.PAS), (0, A.PAS), (1, A.ACE + 0), (1, A.VEND), (1, A.ACCEPTER)):
            r.apply(seat, action)
        r.apply(1, tuple(C.cards_of(r.hand(1))[:3]))
        self.assertEqual(BANKING, r.phase)
        for seat in range(4):
            self.assertIsNone(S.Svaer().act(observe(r, seat)))

    def test_parity_with_ruby(self):
        report = run(SAMPLE, verbose=False)
        self.assertEqual(0, report["failures"])
        self.assertGreater(report["decisions"], 5000)


if __name__ == "__main__":
    unittest.main()
