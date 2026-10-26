"""Search (search.py): sampled worlds never contradict what the deciding
seat knows; searched decisions give one weighted Q row per candidate;
search off is exactly the old self-play; a tiny run trains with it."""

import importlib.util
import random
import tempfile
import unittest
from pathlib import Path

from esmakker_ai import features as F
from esmakker_ai.engine import Round
from esmakker_ai.observation import observe
from esmakker_ai.search import sample_world, world_from

from .test_observation import played_runder, snapshots

HAVE_TORCH = importlib.util.find_spec("torch") is not None and importlib.util.find_spec("numpy") is not None


class WorldTest(unittest.TestCase):
    def test_worlds_never_contradict_the_seat(self):
        """At every state of runder played by random bots (fordækt out of
        turn, banks, sol exchanges and all), for every seat: a world is
        found, it is a legal replay of the same actions, the seat's
        observation and features are the same as in the truth, and they
        were the same at every earlier step too (the seat's memory)."""
        rng = random.Random(5)
        states = found = differ = 0
        for r in played_runder(60, 21):
            for step, _, _ in snapshots(r):
                if step.over():
                    continue
                for seat in range(4):
                    states += 1
                    world = sample_world(step, seat, rng)
                    if world is None:
                        continue
                    found += 1
                    differ += world.deal != step.deal
                    self.assertEqual(observe(step, seat), observe(world, seat))
                    self.assertEqual(F.encode(step, seat), F.encode(world, seat))
                    Round.replay(world.deal, world.dealer, world.log, world.rules)  # legal, with checks
                    if states % 7 == 0:
                        truth = Round(step.deal, step.dealer, step.rules)
                        other = Round(world.deal, world.dealer, world.rules)
                        for (s1, a1), (s2, a2) in zip(step.log, world.log):
                            self.assertEqual(observe(truth, seat), observe(other, seat))
                            truth.apply(s1, a1)
                            other.apply(s2, a2)
        self.assertGreater(states, 3000)
        self.assertGreater(found / states, 0.995)
        self.assertGreater(differ / found, 0.95)  # and they are other worlds, not the truth

    def test_a_world_is_drawn_from_the_observation_alone(self):
        """Two truths the seat cannot tell apart give the same worlds for the
        same random numbers: the draw cannot depend on the hidden cards."""
        rng = random.Random(8)
        checked = 0
        for r in played_runder(20, 4):
            for step, _, _ in snapshots(r):
                if step.over():
                    continue
                seat = rng.randrange(4)
                other = sample_world(step, seat, rng)
                seed = rng.randrange(1 << 30)
                one = world_from(observe(step, seat), step.rules, random.Random(seed))
                two = world_from(observe(other, seat), other.rules, random.Random(seed))
                self.assertEqual(one is None, two is None)
                if one is not None:
                    self.assertEqual(one.deal, two.deal)
                    checked += 1
        self.assertGreater(checked, 300)

    def test_bidding_worlds_keep_only_the_own_hand(self):
        rng = random.Random(2)
        r = Round(list(range(55)), 0)
        for _ in range(20):
            world = sample_world(r, 1, rng)
            self.assertEqual(r.deal_hands[1], world.deal_hands[1])
            self.assertEqual(set(range(55)), set(world.deal))


@unittest.skipUnless(HAVE_TORCH, "PyTorch not installed (pip install -r requirements-train.txt)")
class SearchTrainingTest(unittest.TestCase):
    def setUp(self):
        import torch
        from esmakker_ai.config import Config
        self.torch = torch

        def small(**changes):
            values = dict(seed=5, device="cpu", actors=0, hidden=64, action_hidden=16, batch_size=64,
                          replay_size=4000, min_replay=300, sync_runder=4, sync_updates=3, snapshot_steps=0,
                          snapshot_eval_deals=0, checkpoint_minutes=60, low_priority=False)
            values.update(changes)
            return Config(**values)
        self.small = small

    def test_searched_decisions_give_a_row_per_candidate(self):
        from esmakker_ai.actor import Batch
        from esmakker_ai.agent import Q_TARGET, TARGETS
        from esmakker_ai.net import build
        from esmakker_ai.partners import factory
        from esmakker_ai.rules import STANDARD
        from esmakker_ai.search import SearchingGames
        config = self.small(actor_games=6, search_share=0.05, search_share_bid=0.5, search_k=2, search_random=1,
                            search_worlds=3, search_weight=0.7, partner_share=0.5, search_belief=3)
        model = build(config).eval()
        batch = Batch()
        games = SearchingGames(model, self.torch.device("cpu"), random.Random(3), config, factory("svaer"), STANDARD)
        while batch.runder < 12 or batch.searched < 5:
            games.step(batch)
        states, actions, targets, weights = batch.arrays()
        n = len(batch.actions)
        self.assertEqual(len(states), len(actions))
        self.assertEqual((len(actions), TARGETS), targets.shape)
        self.assertEqual((len(actions), 2), weights.shape)
        self.assertTrue((weights[:n] == 1).all())
        searched = weights[n:]
        self.assertGreater(len(searched), 0)
        self.assertTrue((searched[:, 0] == 0.7).all() and (searched[:, 1] == 0).all())
        # only the points and the Q target: the other heads skip these rows
        self.assertTrue((targets[n:, 1:Q_TARGET] == 0).all() and (targets[n:, Q_TARGET + 1:] == 0).all())
        self.assertTrue((targets[n:, Q_TARGET] != targets[n:, 0]).any())  # the spil's part (actor.spil_steps)
        # 2-3 candidates per searched decision (fewer when it has fewer choices), each a legal choice there
        rows = {}
        for state, action in zip(states[n:], actions[n:]):
            rows.setdefault(state.tobytes(), []).append(int(action))
        for cands in rows.values():
            self.assertTrue(2 <= len(cands) <= 3, cands)
            self.assertEqual(len(cands), len(set(cands)))
        self.assertGreaterEqual(games.stats["searched"], batch.searched)
        self.assertEqual(0, games.stats["no_world"])
        self.assertGreater(games.stats["belief_mismatch"], 0)  # the bids weighed the worlds

    def test_the_actor_plays_the_net_unless_search_is_clearly_better(self):
        """search_play_z: with an impossible margin the searched decisions
        play the net's own choice (and the rows are still made)."""
        from esmakker_ai.actor import Batch
        from esmakker_ai.net import build
        from esmakker_ai.partners import factory
        from esmakker_ai.rules import STANDARD
        from esmakker_ai.search import SearchingGames
        config = self.small(actor_games=4, search_share_bid=1.0, search_worlds=3, search_play_z=1e9,
                            search_explore=0.0)
        games = SearchingGames(build(config).eval(), self.torch.device("cpu"), random.Random(5), config,
                               factory("svaer"), STANDARD)
        batch = Batch()
        while batch.searched < 10:
            games.step(batch)
        self.assertEqual(0, games.stats["changed"])
        self.assertGreater(len(batch.search_rows), 20)

    def test_search_off_is_the_old_self_play(self):
        """search_share = search_share_bid = 0: the actors use BatchedGames
        and the learner the old losses; a weighted replay with all weights 1
        gives the same loss."""
        from esmakker_ai.learner import Trainer
        from esmakker_ai.search import enabled
        self.assertFalse(enabled(self.small()))
        torch = self.torch
        torch.manual_seed(0)
        one = Trainer(self.small())
        for _ in range(40):
            one.sync_round()
        self.assertNotIn("searched", one.counters)
        self.assertFalse(one.replay.weighted)
        two = Trainer(self.small())
        two.model.load_state_dict(one.model.state_dict())
        two.replay.load_state_dict(one.replay.state_dict())
        two.np_rng.bit_generator.state = one.np_rng.bit_generator.state
        two.replay.weighted = True  # the weighted path, all weights 1
        a = one.train_step()
        b = two.train_step()
        for key in a:
            self.assertAlmostEqual(a[key], b[key], places=5)

    def test_a_tiny_run_with_search(self):
        from esmakker_ai.learner import CHECKPOINT, Trainer, train
        config = self.small(search_share=0.02, search_share_bid=0.3, search_worlds=2, search_k=2, min_replay=200,
                            partner_share=0.5)
        with tempfile.TemporaryDirectory() as tmp:
            trainer = train(config, Path(tmp) / "run", max_steps=15, echo=lambda _: None)
            self.assertGreaterEqual(trainer.counters["steps"], 15)
            self.assertGreater(trainer.counters["searched"], 0)
            self.assertTrue(trainer.replay.weighted)
            again = Trainer(config)
            again.load(Path(tmp) / "run" / CHECKPOINT)
            self.assertTrue(again.replay.weighted)
            self.assertTrue((again.replay.weights[:again.replay.count] == trainer.replay.weights[:trainer.replay.count]).all())


if __name__ == "__main__":
    unittest.main()
