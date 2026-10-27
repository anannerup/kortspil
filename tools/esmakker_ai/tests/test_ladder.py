"""The ladder (ladder.py): each snapshot in same-hand duplicate against the
run's earlier ones. Small nets on the CPU. Skipped without PyTorch."""

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

HAVE_TORCH = importlib.util.find_spec("torch") is not None

if HAVE_TORCH:
    import torch

    from esmakker_ai import ladder
    from esmakker_ai.learner import SNAPSHOTS, Trainer
    from esmakker_ai.net import build
    from tests.test_training import small


class PlanTest(unittest.TestCase):
    def test_each_snapshot_meets_its_gate_and_a_spread_of_the_others(self):
        files = [f"s{i}" for i in range(12)]
        plan = ladder.plan(files, gap=3, most=4) if HAVE_TORCH else []
        if not HAVE_TORCH:
            self.skipTest("PyTorch not installed")
        gates = {new: old for new, old, kind in plan if kind == "gate"}
        self.assertEqual("s0", gates["s1"])  # fewer than 3 before: the first one
        self.assertEqual("s0", gates["s3"])
        self.assertEqual("s8", gates["s11"])
        others = [old for new, old, kind in plan if new == "s11" and kind == "all"]
        self.assertEqual(4, len(others))
        self.assertNotIn("s8", others)
        self.assertNotIn("s0", gates)  # the first has nothing before it
        self.assertEqual(["s0", "s1"], sorted(old for new, old, _ in plan if new == "s2"))


@unittest.skipUnless(HAVE_TORCH, "PyTorch not installed (pip install -r requirements-train.txt)")
class LadderTest(unittest.TestCase):
    def snapshots(self, tmp, count):
        config = small()
        paths = []
        for i in range(count):
            torch.manual_seed(i)
            trainer = Trainer(config)
            trainer.counters["steps"] = 1000 * (i + 1)
            paths.append(trainer.save_snapshot(tmp))
        (Path(tmp) / "config.json").write_text(json.dumps(config.to_dict()))
        return config, paths

    def test_a_net_against_itself_is_exactly_even(self):
        model = build(small()).eval()
        for i in range(8):
            self.assertEqual((0.0, 0.0), ladder.deal_diffs(model, model, i, 5))

    def test_the_paired_difference_is_the_seats_own_doing(self):
        torch.manual_seed(1)
        a = build(small()).eval()
        torch.manual_seed(2)
        b = build(small()).eval()
        for i in range(6):
            x, y = ladder.deal_diffs(a, b, i, 5)
            rx, ry = ladder.deal_diffs(b, a, i, 5)
            # swapping the nets flips both signs (the fields swap with them)
            self.assertAlmostEqual(x, -ry)
            self.assertAlmostEqual(y, -rx)

    def test_run_pending_writes_each_comparison_once(self):
        with tempfile.TemporaryDirectory() as tmp:
            config, paths = self.snapshots(tmp, 3)
            config.ladder_deals, config.ladder_deals_all, config.ladder_gap, config.ladder_all_most = 6, 3, 3, 4
            written = ladder.run_pending(tmp, config, workers=1, echo=lambda *_: None)
            self.assertEqual({("step_000002000.pt", "step_000001000.pt", "gate"),
                              ("step_000003000.pt", "step_000001000.pt", "gate"),
                              ("step_000003000.pt", "step_000002000.pt", "all")},
                             {(e["file"], e["vs"], e["kind"]) for e in written})
            gate = next(e for e in written if e["kind"] == "gate")
            self.assertEqual(12, gate["runder"])  # 6 deals x 2 fields
            self.assertEqual(6, gate["diff"]["n"])
            self.assertEqual(written, ladder.read(tmp))
            self.assertEqual([], ladder.run_pending(tmp, config, workers=1, echo=lambda *_: None))
            self.assertTrue(all((Path(tmp) / SNAPSHOTS / e["vs"]).exists() for e in written))


if __name__ == "__main__":
    unittest.main()
