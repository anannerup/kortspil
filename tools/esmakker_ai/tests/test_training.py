"""Training (PyTorch): a resumed run continues exactly; start, stop and
resume work; the net plays legal runder and evaluates against FirstBot.
CPU only, small nets. Skipped when PyTorch is not installed."""

import importlib.util
import random
import tempfile
import threading
import time
import unittest
from pathlib import Path

HAVE_TORCH = importlib.util.find_spec("torch") is not None and importlib.util.find_spec("numpy") is not None

if HAVE_TORCH:
    import torch

    from esmakker_ai import actions as A
    from esmakker_ai import features as F
    from esmakker_ai.actor import Batch, BatchedGames, play_game
    from esmakker_ai.partners import factory
    from esmakker_ai.agent import NetPlayer, explain, play
    from esmakker_ai.bots import FirstBot
    from esmakker_ai.config import Config, IncompatibleRun
    from esmakker_ai.rating import elo, rate, share_of
    from esmakker_ai.rules import STANDARD
    from esmakker_ai.train import main as train_main
    from esmakker_ai.engine import PLAYING, Round
    from esmakker_ai.evaluate import duplicate
    from esmakker_ai.learner import CHECKPOINT, STOP, Run, Trainer, load_weights, train
    from esmakker_ai.net import build
    from esmakker_ai.selfplay import random_deal


def small(**changes):
    values = dict(seed=5, device="cpu", actors=0, hidden=64, action_hidden=16, batch_size=64, replay_size=4000,
                  min_replay=300, sync_runder=4, sync_updates=3, snapshot_steps=0, snapshot_eval_deals=0,
                  checkpoint_minutes=60, low_priority=False)
    values.update(changes)
    return Config(**values)


@unittest.skipUnless(HAVE_TORCH, "PyTorch not installed (pip install -r requirements-train.txt)")
class ResumeTest(unittest.TestCase):
    def test_a_resumed_run_continues_exactly(self):
        torch.use_deterministic_algorithms(True)
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "ck.pt"
            one = Trainer(small())
            for _ in range(30):
                one.sync_round()
            self.assertGreater(one.counters["steps"], 5)
            one.save(path)
            for _ in range(10):
                one.sync_round()

            two = Trainer(small())
            two.load(path)
            for _ in range(10):
                two.sync_round()

        self.assertEqual(one.counters, two.counters)
        for (name, a), (_, b) in zip(one.model.state_dict().items(), two.model.state_dict().items()):
            self.assertTrue(torch.equal(a, b), name)
        self.assertEqual(one.replay.pos, two.replay.pos)
        self.assertTrue((one.replay.states == two.replay.states).all())
        self.assertEqual(one.play_rng.getstate(), two.play_rng.getstate())

    def test_start_stop_resume(self):
        with tempfile.TemporaryDirectory() as tmp:
            run_dir = Path(tmp) / "run"
            first = train(small(), run_dir, max_steps=8, echo=lambda *_: None)
            self.assertTrue((run_dir / CHECKPOINT).exists())
            self.assertEqual("stopped", Run(run_dir).status()["state"])
            steps = first.counters["steps"]

            # a stop asked from outside (what `train stop` does) while it runs
            done = {}
            thread = threading.Thread(target=lambda: done.update(t=train(small(), run_dir, echo=lambda *_: None)))
            thread.start()
            deadline = time.time() + 30
            while not Run(run_dir).running() and time.time() < deadline:
                time.sleep(0.05)
            (run_dir / STOP).write_text("stop\n")
            thread.join(60)
            self.assertFalse(thread.is_alive())
            second = done["t"]
            self.assertEqual(1, second.counters["resumes"])
            self.assertGreaterEqual(second.counters["steps"], steps)
            self.assertFalse((run_dir / STOP).exists())
            self.assertEqual("stopped", Run(run_dir).status()["state"])

    def test_actor_processes(self):
        with tempfile.TemporaryDirectory() as tmp:
            config = small(actors=2, min_replay=1000, weights_every=2)
            trainer = train(config, Path(tmp) / "run", max_steps=5, echo=lambda *_: None)
            self.assertEqual(5, trainer.counters["steps"])
            self.assertGreater(trainer.counters["runder"], 0)
            model, saved = load_weights(Path(tmp) / "run" / CHECKPOINT)
            self.assertEqual(5, saved["counters"]["steps"])


@unittest.skipUnless(HAVE_TORCH, "PyTorch not installed (pip install -r requirements-train.txt)")
class FormatTest(unittest.TestCase):
    def test_an_old_run_refuses_to_resume_with_a_clear_message(self):
        import contextlib
        import io
        import json
        with tempfile.TemporaryDirectory() as tmp:
            run_dir = Path(tmp) / "old"
            run_dir.mkdir()
            old = small().to_dict()
            old["rules"] = None  # format 1 wrote no format, and had a rules setting
            (run_dir / "config.json").write_text(json.dumps(old))
            (run_dir / CHECKPOINT).write_bytes(b"not a checkpoint of this format")
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                code = train_main(["start", "--runs-dir", tmp, "--run", "old"])
            self.assertEqual(1, code)
            self.assertIn("start a new run with --run NAME", out.getvalue())
            with self.assertRaises(IncompatibleRun):
                train(small(), run_dir, max_steps=1, echo=lambda *_: None)

    def test_an_old_checkpoint_does_not_load(self):
        with tempfile.TemporaryDirectory() as tmp:
            trainer = Trainer(small())
            state = trainer.state_dict()
            state.pop("format")
            torch.save(state, Path(tmp) / "ck.pt")
            with self.assertRaisesRegex(IncompatibleRun, "--run NAME"):
                Trainer(small()).load(Path(tmp) / "ck.pt")
            with self.assertRaises(IncompatibleRun):
                load_weights(Path(tmp) / "ck.pt")


@unittest.skipUnless(HAVE_TORCH, "PyTorch not installed (pip install -r requirements-train.txt)")
class RatingTest(unittest.TestCase):
    def test_the_scale(self):
        self.assertAlmostEqual(0.0, elo(0.25))
        self.assertAlmostEqual(0.5, share_of(400 * __import__("math").log10(3)))
        for rating in (-300, -50, 0, 120, 400):
            self.assertAlmostEqual(rating, elo(share_of(rating)))

    def test_firstbot_rates_zero_against_itself(self):
        report = rate("first", spil=12, seed=2)
        self.assertEqual(0.0, report["rating"])
        self.assertEqual([0.0, 0.0], report["rating_ci"])

    def test_rating_command_rates_snapshots_and_writes_csv(self):
        import contextlib
        import io
        import json
        with tempfile.TemporaryDirectory() as tmp:
            run_dir = Path(tmp) / "r"
            train(small(snapshot_steps=4, sync_updates=1, rating_spil=0), run_dir, max_steps=8, echo=lambda *_: None)
            from esmakker_ai import config as cfg
            cfg.save(small(snapshot_steps=4, sync_updates=1, rating_spil=0), run_dir / "config.json")
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                code = train_main(["rating", "--runs-dir", tmp, "--run", "r", "--all", "--spil", "4", "--deals", "2",
                                   "--csv"])
                train_main(["status", "--runs-dir", tmp, "--run", "r"])
            self.assertEqual(0, code, out.getvalue())
            ratings = [json.loads(line) for line in (run_dir / "ratings.jsonl").read_text().splitlines()]
            self.assertEqual([4, 8], [e["step"] for e in ratings])
            for e in ratings:
                self.assertLessEqual(e["rating_ci"][0], e["rating"])
                self.assertIn("mean", e["vs_svaer"])
                self.assertIn("mean", e["vs_pass"])
            self.assertTrue((run_dir / "ratings.csv").exists())
            self.assertIn("latest rating: step 8", out.getvalue())


@unittest.skipUnless(HAVE_TORCH, "PyTorch not installed (pip install -r requirements-train.txt)")
class PlayTest(unittest.TestCase):
    def test_the_net_plays_legal_runder_and_never_banks(self):
        model = build(small()).eval()
        rng = random.Random(2)
        for index in range(60):
            players = [NetPlayer(model, 0.2, rng) for _ in range(4)]
            players[index % 4] = FirstBot(index)
            r = Round(random_deal(rng), index % 4)
            log_before = len(r.log)
            play(r, players)
            self.assertTrue(r.over())
            self.assertGreater(len(r.log), log_before)
            self.assertEqual([], r.banks)
            # replaying with checks proves every action was legal
            Round.replay(r.deal, r.dealer, r.log)

    def test_batched_games_choose_as_one_at_a_time(self):
        """BatchedGames (the actors' GPU path, here on the CPU) makes the same
        samples as play_game when it plays one runde at a time."""
        config = small(epsilon=0.0, bid_epsilon=0.0, partner_share=0.0)
        model = build(config).eval()
        one, many = Batch(), Batch()
        rng = random.Random(4)
        for _ in range(6):
            play_game(model, rng, config, None, STANDARD, one)
        games = BatchedGames(model, torch.device("cpu"), random.Random(4), config, None, STANDARD)
        while many.runder < 6:
            games.step(many)
        for a, b in zip(one.arrays(), many.arrays()):
            self.assertTrue((a == b[:len(a)]).all())

    def test_batched_games_play_many_runder_at_once(self):
        config = small(actor_games=8)
        batch = Batch()
        games = BatchedGames(build(config).eval(), torch.device("cpu"), random.Random(1), config,
                             factory(config.partner), STANDARD)
        while batch.runder < 20:
            games.step(batch)
        self.assertGreater(len(batch), 20 * 10)

    def test_the_net_chooses_how_many_to_exchange_and_fordaekt_out_of_turn(self):
        """A random net (epsilon 1) exchanges 0, 1, 2 and 3 cards, and as a
        melder who is not forhånd it is asked about fordækt before the
        forhånd leads, and sometimes lays it; all of it legal."""
        model = build(small()).eval()
        rng = random.Random(4)
        stats = {}
        offered = laid = 0
        for index in range(800):
            net = NetPlayer(model, 1.0, rng)
            r = Round(random_deal(rng), index % 4)
            decisions = play(r, [net] * 4, record=(0, 1, 2, 3), stats=stats)
            Round.replay(r.deal, r.dealer, r.log)
            if r.kind == "stik" and r.melder != r.forhand:
                actions = [a for _, a in decisions[r.melder]]
                offered += F.NO_FORDAEKT in actions or any(A.FORDAEKT <= a < A.ACTION_COUNT for a in actions)
                laid += r.fordaekt is not None
        self.assertTrue(all(stats["exchanged"]), stats)
        self.assertTrue(stats["sol_exchanged"][0] or stats["sol_exchanged"][3], stats)
        self.assertGreater(offered, 3)
        self.assertGreater(laid, 0)

    def test_training_uses_only_the_house_rules(self):
        from esmakker_ai.actor import rules_of
        self.assertIs(STANDARD, rules_of(Config()))
        self.assertFalse(hasattr(Config(), "rules"))
        with self.assertRaises(ValueError):
            Config.from_dict({"rules": {"joker_trumpable": True}})

    def test_explain(self):
        model = build(small()).eval()
        rng = random.Random(3)
        r = Round(random_deal(rng), 0)
        players = [FirstBot(s) for s in range(4)]
        while r.phase != PLAYING and not r.over():
            seat = r.to_act()
            if seat is None:
                break
            from esmakker_ai.observation import observe
            r.apply(seat, players[seat].act(observe(r, seat)))
        seat = r.to_act() if not r.over() else 0
        info = explain(model, r, seat)
        self.assertAlmostEqual(1.0, sum(info["ace_holder"].values()), places=5)
        self.assertEqual({"actions", "points", "own_stik", "makker_stik", "ace_holder"}, set(info))

    def test_a_tiny_run_beats_firstbot(self):
        """A few hundred learner steps learn at least not to throw points
        away like FirstBot (it melder 9 whenever it may and plays at random)."""
        torch.manual_seed(0)
        trainer = Trainer(small(hidden=128, action_hidden=32, batch_size=128, min_replay=1000, sync_runder=8,
                                sync_updates=4, lr=1e-3))
        while trainer.counters["steps"] < 300:
            trainer.sync_round()
        report = duplicate(trainer.cpu_copy(), deals=150, seed=3)
        self.assertGreater(report["diff"]["mean"], 0, report)


if __name__ == "__main__":
    unittest.main()
