"""The spil (FORMAT 3): a runde's place in its spil and the standing in the
net's input, the spil's part of the training targets, self-play of whole
spil, and a new run warm-started from a FORMAT 2 net."""

import importlib.util
import random
import tempfile
import unittest
from pathlib import Path

from esmakker_ai import features as F
from esmakker_ai import meldinger as M
from esmakker_ai.engine import Round
from esmakker_ai.spil import START, SpilContext, expected_outcome, margin, outcome, win_share
from tests.test_observation import hidden_variant, played_runder

HAVE_TORCH = importlib.util.find_spec("torch") is not None and importlib.util.find_spec("numpy") is not None
NEW_BITS = ((1 << F.STATE_BITS) - 1) ^ ((1 << F.FORMAT2_STATE_BITS) - 1)


def field(x, offset, width):
    return (x >> offset) & ((1 << width) - 1)


def diff_of(bits):
    """The thermometer's reading: the largest threshold reached, signed (0: none)."""
    n = len(F.DIFF_THRESHOLDS)
    up = [t for i, t in enumerate(F.DIFF_THRESHOLDS) if bits >> i & 1]
    down = [t for i, t in enumerate(F.DIFF_THRESHOLDS) if bits >> (n + i) & 1]
    assert not (up and down)
    return max(up) if up else -max(down) if down else 0


class SpilFeaturesTest(unittest.TestCase):
    def test_the_layout_appends_to_format_2(self):
        self.assertEqual(3, F.FORMAT)
        self.assertEqual(1192, F.FORMAT2_STATE_BITS)
        self.assertEqual(F.FORMAT2_STATE_BITS, F.RUNDER_LEFT)
        self.assertLessEqual(F.RANK + 4, F.STATE_BITS)

    def test_no_context_is_the_first_runde_and_touches_only_its_bits(self):
        ctx = SpilContext(6, 10, (12.5, -3.0, -8.0, -1.5))
        for r in played_runder(20, seed=2):
            for seat in range(4):
                plain = F.encode(r, seat)
                self.assertEqual(plain, F.encode(r, seat, spil=START))
                with_ctx = F.encode(r, seat, spil=ctx)
                self.assertEqual(0, (plain ^ with_ctx) & ~NEW_BITS)
                self.assertEqual(F.spil_bits(ctx, seat), with_ctx & NEW_BITS)

    def test_the_standing_relative_to_the_seat(self):
        totals = (10.0, 0.0, -4.0, -6.0)
        ctx = SpilContext(3, 10, totals)
        r = Round(list(range(55)), 0)
        for seat in range(4):
            x = F.encode(r, seat, spil=ctx)
            self.assertEqual(1 << (7 - 1), field(x, F.RUNDER_LEFT, F.SPIL_SLOTS))  # 7 left, this one included
            self.assertEqual(1 << 3, field(x, F.RUNDE_NO, F.SPIL_SLOTS))
            ahead = sum(1 for t in totals if t > totals[seat])
            self.assertEqual(1 << ahead, field(x, F.RANK, 4))
            for k in (1, 2, 3):
                diff = totals[(seat + k) % 4] - totals[seat]
                reading = diff_of(field(x, F.BEHIND[k], F.DIFF_WIDTH))
                self.assertLessEqual(abs(reading), abs(diff))
                self.assertEqual(diff > 0, reading > 0)
                self.assertEqual(diff < 0, reading < 0)
            lead = totals[seat] - max(totals[(seat + k) % 4] for k in (1, 2, 3))
            self.assertEqual(lead > 0, diff_of(field(x, F.LEAD, F.DIFF_WIDTH)) > 0)
        # the leader reads 10 ahead: thresholds up to 10 reached, 14 not
        lead_bits = field(F.encode(r, 0, spil=ctx), F.LEAD, F.DIFF_WIDTH)
        self.assertEqual(10, diff_of(lead_bits))
        # a long spil: runder left and the runde number saturate
        x = F.encode(r, 0, spil=SpilContext(17, 40, totals))
        self.assertEqual(1 << 15, field(x, F.RUNDER_LEFT, F.SPIL_SLOTS))
        self.assertEqual(1 << 15, field(x, F.RUNDE_NO, F.SPIL_SLOTS))

    def test_hidden_worlds_stay_apart_with_a_context(self):
        """The standing is public; with it, a seat still cannot tell hidden
        worlds apart (the full check is test_features.NoLeakTest)."""
        rng = random.Random(8)
        ctx = SpilContext(4, 10, (3.0, -1.5, 0.0, -1.5))
        compared = 0
        for r in played_runder(60, seed=8):
            if r.melder is None:
                continue
            observer = rng.randrange(4)
            one = Round(r.deal, r.dealer, r.rules)
            two = Round(hidden_variant(r, observer, rng), r.dealer, r.rules)
            for seat, action in r.log[:12]:
                if r.kind == "stik" and M.pahaeng(r.melding) == M.HALVE and one.called_ace is not None:
                    break  # at halve the ace holder gives herself away to all (as test_features)
                self.assertEqual(F.encode(one, observer, spil=ctx), F.encode(two, observer, spil=ctx))
                compared += 1
                one.apply(seat, action)
                try:
                    two.apply(seat, action)
                except Exception:  # noqa: BLE001 - the worlds part where the hidden cards matter
                    break
        self.assertGreater(compared, 100)


class OutcomeTest(unittest.TestCase):
    def test_win_share_and_margin(self):
        totals = (5, 5, -4, -6)
        self.assertEqual([0.5, 0.5, 0.0, 0.0], [win_share(totals, s) for s in range(4)])
        self.assertEqual([0, 0, -9, -11], [margin(totals, s) for s in range(4)])
        self.assertEqual(([10, -10, -12, -14], [1.0, 0, 0, 0]), outcome((10, 0, -2, -4)))

    def test_the_expected_outcome(self):
        margins, wins = expected_outcome((0, 0, 0, 0), 10, 4.7)
        self.assertEqual([0.25] * 4, wins)
        self.assertTrue(all(abs(m - margins[0]) < 1e-9 for m in margins))
        self.assertEqual(outcome((7, -1, -3, -3)), expected_outcome((7, -1, -3, -3), 0, 4.7))
        # ahead is better, and more so with fewer runder left
        early = expected_outcome((5, -5 / 3, -5 / 3, -5 / 3), 9, 4.7)
        late = expected_outcome((5, -5 / 3, -5 / 3, -5 / 3), 1, 4.7)
        self.assertGreater(early[1][0], 0.25)
        self.assertGreater(late[1][0], early[1][0])
        self.assertGreater(early[0][0], margins[0])

    def test_a_big_win_is_worth_more_than_a_narrow_one(self):
        from esmakker_ai.agent import spil_targets
        from esmakker_ai.config import Config
        config = Config(spil_weight=0.5, win_value=20.0)
        before = expected_outcome((0, 0, 0, 0), 1, 4.7)  # the last runde, all level

        def q(points):  # seat 0 wins `points`, the three others pay a third each
            totals = (points, -points / 3, -points / 3, -points / 3)
            return spil_targets(points, before, outcome(totals), 0, config)
        values = [q(p) for p in (-9, -3, -1, 1, 3, 9)]
        self.assertEqual(values, sorted(values))
        self.assertGreater(q(1) - q(-1), 2 + config.spil_weight * config.win_value)  # crossing the top pays the bonus

    def test_the_expected_changes_add_up_to_the_outcome(self):
        """Summed over a spil, the runde-by-runde changes in the expected
        outcome are the actual outcome less the expected one at the start."""
        rng = random.Random(1)
        totals = [0.0] * 4
        steps = []
        for played in range(10):
            before = expected_outcome(totals, 10 - played, 4.7)
            points = [rng.choice((-3.0, -1.5, 1.5, 3.0)) for _ in range(3)]
            points.append(-sum(points))
            totals = [t + p for t, p in zip(totals, points)]
            steps.append((before, expected_outcome(totals, 9 - played, 4.7)))
        final = outcome(totals)
        start = expected_outcome((0, 0, 0, 0), 10, 4.7)
        for seat in range(4):
            for k in (0, 1):
                total = sum(after[k][seat] - before[k][seat] for before, after in steps)
                self.assertAlmostEqual(final[k][seat] - start[k][seat], total, places=9)


@unittest.skipUnless(HAVE_TORCH, "PyTorch not installed (pip install -r requirements-train.txt)")
class SelfPlayTest(unittest.TestCase):
    def test_self_play_plays_whole_spil_and_the_net_sees_the_standing(self):
        import esmakker_ai.actor as actor
        from esmakker_ai.agent import Q_TARGET, WIN_TARGET
        from esmakker_ai.net import build
        from esmakker_ai.partners import factory
        from esmakker_ai.rules import STANDARD
        from tests.test_training import small

        seen = []
        original = actor.play_steps

        def recording(r, players, record=(), stats=None, bidders=None, spil=None):
            decisions = yield from original(r, players, record, stats, bidders, spil)
            seen.append((r, spil, {s: list(d) for s, d in decisions.items()}))
            return decisions

        actor.play_steps = recording
        try:
            config = small(partner_share=0.5, partner="first", runder=6)
            model = build(config).eval()
            rng = random.Random(9)
            for _ in range(4):
                seen.clear()
                batch = actor.Batch()
                actor.play_game(model, rng, config, factory("first"), STANDARD, batch)
                totals, played, dealer = [0.0] * 4, 0, seen[0][0].dealer
                for r, spil, decisions in seen:
                    self.assertEqual(SpilContext(played, 6, tuple(totals)), spil)
                    self.assertEqual(dealer, r.dealer)  # the kortgiver moves on (a redeal: as the engine says)
                    for seat, chosen in decisions.items():
                        for state, _ in chosen:
                            x = int.from_bytes(state, "little")
                            self.assertEqual(F.spil_bits(spil, seat), x & NEW_BITS)
                    if r.complete():
                        totals = [t + float(p) for t, p in zip(totals, r.points())]
                        played += 1
                    dealer = r.next_dealer()
                self.assertEqual(6, played)
                self.assertEqual(len(seen), batch.runder)
                self.assertEqual(1, batch.spil)
                _, _, targets = batch.arrays()
                recorded = sorted({s for _, _, d in seen for s in d})
                wins = sorted({float(t) for t in targets[:, WIN_TARGET]})
                self.assertTrue(set(wins) <= {win_share(totals, s) for s in recorded})
                self.assertTrue((targets[:, Q_TARGET] == targets[:, Q_TARGET]).all())  # no NaN
        finally:
            actor.play_steps = original


@unittest.skipUnless(HAVE_TORCH, "PyTorch not installed (pip install -r requirements-train.txt)")
class WarmStartTest(unittest.TestCase):
    def old_snapshot(self, folder, config):
        """A FORMAT 2 snapshot: a net with the old input size and no win head."""
        import torch
        from esmakker_ai.net import EsmakkerNet
        torch.manual_seed(3)
        old = EsmakkerNet(config.hidden, config.action_hidden, config.points_scale, F.FORMAT2_STATE_BITS)
        for p in old.parameters():  # not just the init: make every weight count
            p.data.normal_(0, 0.2)
        weights = {k: v for k, v in old.state_dict().items() if not k.startswith("win.")}
        path = Path(folder) / "step_old.pt"
        torch.save({"format": 2, "config": {k: v for k, v in config.to_dict().items()
                                            if k not in ("runder", "spil_weight", "win_value", "spil_target",
                                                         "runde_sd", "win_weight")},
                    "model": weights, "counters": {"steps": 7, "runder": 1}}, path)
        return old.eval(), path

    def test_the_warm_net_chooses_as_the_old_one(self):
        import numpy as np
        import torch
        from esmakker_ai.agent import ACTION_TABLE
        from esmakker_ai.learner import warm_start
        from esmakker_ai.net import build, unpack
        from tests.test_training import small
        config = small()
        with tempfile.TemporaryDirectory() as tmp:
            old, path = self.old_snapshot(tmp, config)
            new = build(config)
            lines = warm_start(new, path)
        new.eval()
        self.assertIn("format 2", lines[0])
        first = new.state_dict()["state.0.weight"]
        self.assertTrue(torch.equal(first[:, F.FORMAT2_STATE_BITS:], torch.zeros_like(first[:, F.FORMAT2_STATE_BITS:])))
        rng = random.Random(4)
        decisions = same = 0
        for r in played_runder(15, seed=4):
            replay = Round(r.deal, r.dealer, r.rules)
            for seat, action in r.log:
                for observer in range(4):
                    cands = F.candidates(replay, observer)
                    if len(cands) < 2:
                        continue
                    ctx = SpilContext(rng.randrange(10), 10, tuple(rng.uniform(-20, 20) for _ in range(4)))
                    state = unpack(np.frombuffer(F.to_bytes(F.encode(replay, observer, spil=ctx)), np.uint8))[None]
                    s_new = torch.from_numpy(state)
                    s_old = s_new[:, :F.FORMAT2_STATE_BITS]
                    a = torch.from_numpy(ACTION_TABLE[cands])
                    with torch.inference_mode():
                        q_new = new.q_values(new.encode_state(s_new).expand(len(cands), -1), a)
                        q_old = old.q_values(old.encode_state(s_old).expand(len(cands), -1), a)
                        h_new, h_old = new.heads(new.encode_state(s_new)), old.heads(old.encode_state(s_old))
                    self.assertTrue(torch.allclose(q_new, q_old, atol=1e-5))
                    for head in ("value", "stik", "makker"):
                        self.assertTrue(torch.allclose(h_new[head], h_old[head], atol=1e-5))
                    decisions += 1
                    same += int(q_new.argmax()) == int(q_old.argmax())
                replay.apply(seat, action)
        self.assertGreater(decisions, 300)
        self.assertEqual(decisions, same)

    def test_train_start_init_from_format_2_trains(self):
        """End to end: `train start --init` from a FORMAT 2 snapshot, a few
        learner steps on whole spil, then the run's checkpoint rates."""
        import contextlib
        import io
        from esmakker_ai import config as cfg
        from esmakker_ai.learner import CHECKPOINT, load_weights
        from esmakker_ai.train import main as train_main
        from tests.test_training import small
        config = small(min_replay=400, sync_runder=10)
        with tempfile.TemporaryDirectory() as tmp:
            _, path = self.old_snapshot(tmp, config)
            (Path(tmp) / "conf.json").write_text(__import__("json").dumps(config.to_dict()))
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                code = train_main(["start", "--runs-dir", tmp, "--run", "warm", "--config", str(Path(tmp) / "conf.json"),
                                   "--init", str(path), "--max-steps", "6"])
            self.assertEqual(0, code, out.getvalue())
            self.assertIn("the new columns start at 0", out.getvalue())
            model, saved = load_weights(Path(tmp) / "warm" / CHECKPOINT)
            self.assertEqual(6, saved["counters"]["steps"])
            self.assertGreaterEqual(saved["counters"]["spil"], 1)
            self.assertIn("win", saved_losses(Path(tmp) / "warm"))
            from esmakker_ai.rating import rate
            report = rate("net", model, cfg.Config.from_dict(saved["config"]), spil=4, seed=1)
            self.assertEqual(4, report["spil"])

    def test_an_older_format_still_refuses(self):
        import torch
        from esmakker_ai.config import IncompatibleRun
        from esmakker_ai.learner import warm_start
        from esmakker_ai.net import build
        from tests.test_training import small
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "f1.pt"
            torch.save({"config": small().to_dict(), "model": {}}, path)
            with self.assertRaises(IncompatibleRun):
                warm_start(build(small()), path)


def saved_losses(run_dir):
    import json
    return json.loads((run_dir / "status.json").read_text())["losses"]


if __name__ == "__main__":
    unittest.main()
