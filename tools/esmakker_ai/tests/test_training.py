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

    from esmakker_ai.agent import NetPlayer, explain, play
    from esmakker_ai.bots import FirstBot
    from esmakker_ai.config import Config
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
