"""The first bot (docs/bots/esmakker-strategy.md §2) and self-play."""

import random
import unittest

from esmakker_ai import actions as A
from esmakker_ai import meldinger as M
from esmakker_ai.bots import NINE, FirstBot, RandomBot
from esmakker_ai.engine import Round
from esmakker_ai.observation import observe
from esmakker_ai.selfplay import play_runde, play_spil, random_deal


class Recording:
    """Wraps a bot and keeps each observation with the bot's answer."""

    def __init__(self, bot):
        self.bot = bot
        self.decisions = []

    def act(self, obs):
        action = self.bot.act(obs)
        self.decisions.append((obs, action))
        return action


class FirstBotTest(unittest.TestCase):
    def play(self, seeds=300):
        """FirstBot in a random seat among random bots, which bid, go with
        and bank; returns its decisions."""
        decisions = []
        rng = random.Random(21)
        for seed in range(seeds):
            first = rng.randrange(4)
            bots = [RandomBot(seed * 4 + seat) for seat in range(4)]
            bots[first] = Recording(FirstBot(seed))
            play_runde(Round(random_deal(rng), rng.randrange(4)), bots)
            decisions.extend(bots[first].decisions)
        return decisions

    def test_melder_9_when_legal_otherwise_pas(self):
        bidding = [(obs, action) for obs, action in self.play() if obs["phase"] == "bidding"]
        self.assertTrue(any(action == NINE for _, action in bidding))
        self.assertTrue(any(NINE not in obs["legal_actions"] for obs, _ in bidding))
        offered_med = 0
        for obs, action in bidding:
            self.assertEqual(NINE if NINE in obs["legal_actions"] else A.PAS, action)
            offered_med += A.MED in obs["legal_actions"]
        self.assertGreater(offered_med, 0, "it was offered to go with on a sol-melding and said pas")

    def test_never_banks_and_otherwise_plays_a_random_legal_move(self):
        decisions = self.play()
        banking = [action for obs, action in decisions if obs["phase"] == "banking"]
        self.assertTrue(banking)
        self.assertTrue(all(action is None for action in banking))
        for obs, action in decisions:
            if obs["phase"] in ("bidding", "banking"):
                continue
            if obs["discard_size"]:
                self.assertLessEqual(len(action), obs["discard_size"])
                self.assertEqual(len(action), len(set(action)))
                self.assertTrue(set(action) <= set(obs["hand"]))
            else:
                self.assertIn(action, obs["legal_actions"])

    def test_four_first_bots_play_9_from_the_forhand(self):
        rounds, totals = play_spil([FirstBot(seat) for seat in range(4)], runder=20, seed=3)
        self.assertEqual(20, len(rounds))
        for r in rounds:
            self.assertEqual(M.stik(9), r.melding)
            self.assertEqual(r.forhand, r.melder)
            self.assertEqual([], r.banks)
        self.assertEqual(0, sum(totals))

    def test_a_seeded_bot_is_deterministic(self):
        def log(seed):
            rounds, _ = play_spil([FirstBot(seed + seat) for seat in range(4)], runder=5, seed=seed)
            return [r.tokens() for r in rounds]

        self.assertEqual(log(8), log(8))
        self.assertNotEqual(log(8), log(9))

    def test_it_reads_only_the_observation(self):
        r = Round(random_deal(random.Random(4)), 0)
        obs = observe(r, r.to_act())
        self.assertNotIn("hands", obs)
        self.assertEqual(NINE, FirstBot(1).act(obs))


if __name__ == "__main__":
    unittest.main()
