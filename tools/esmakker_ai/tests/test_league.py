"""The league (config league_share): seats played by earlier snapshots of
the run, scored by the inference server, give no samples. CPU only, small
nets. Skipped when PyTorch is not installed."""

import importlib.util
import multiprocessing as mp
import random
import tempfile
import threading
import unittest
from multiprocessing import shared_memory
from pathlib import Path

HAVE_TORCH = importlib.util.find_spec("torch") is not None and importlib.util.find_spec("numpy") is not None

if HAVE_TORCH:
    import numpy as np
    import torch

    from esmakker_ai import inference
    from esmakker_ai.actor import Batch, BatchedGames, LeaguePlayer, NetStub, new_spil
    from esmakker_ai.agent import ACTION_TABLE
    from esmakker_ai.learner import SNAPSHOTS, Trainer, train
    from esmakker_ai.net import build, score_arrays
    from esmakker_ai.partners import factory
    from esmakker_ai.rules import STANDARD
    from tests.test_training import small


class _Count:
    def __init__(self, value):
        self.value = value


def snapshot(config, run_dir, steps, seed):
    """A snapshot of a fresh net (its own random weights) at `steps`."""
    torch.manual_seed(seed)
    trainer = Trainer(config)
    trainer.counters["steps"] = steps
    return trainer.save_snapshot(run_dir)


@unittest.skipUnless(HAVE_TORCH, "PyTorch not installed (pip install -r requirements-train.txt)")
class LeagueTest(unittest.TestCase):
    def test_league_seats_give_no_samples(self):
        config = small(partner_share=0.0, league_share=1.0)
        model = NetStub(False, 10.0, _Count(2))
        seen = set()
        for seed in range(40):
            players, record, net_only = new_spil(model, random.Random(seed), config, None)
            league = [s for s, p in enumerate(players) if isinstance(p, LeaguePlayer)]
            self.assertTrue(net_only)
            self.assertTrue(1 <= len(league) <= 3)
            self.assertEqual(sorted(set(range(4)) - set(league)), sorted(record))
            self.assertEqual(1, len({players[s].slot for s in league}))  # one earlier snapshot per spil
            seen.add(players[league[0]].slot)
        self.assertEqual({1, 2}, seen)

    def test_no_league_before_the_server_holds_a_snapshot_or_when_off(self):
        for config, count in ((small(partner_share=0.0, league_share=1.0), 0), (small(partner_share=0.0), 3)):
            players, record, _ = new_spil(NetStub(False, 10.0, _Count(count)), random.Random(1), config, None)
            self.assertEqual((0, 1, 2, 3), record)
            self.assertFalse(any(isinstance(p, LeaguePlayer) for p in players))

    def test_league_decisions_are_scored_by_the_old_snapshot(self):
        config = small()
        torch.manual_seed(1)
        current, old = build(config).eval(), build(config).eval()
        actions = torch.from_numpy(ACTION_TABLE)
        rng = np.random.default_rng(0)
        n = 30
        packed = rng.integers(0, 256, size=(n, inference.F.STATE_BYTES), dtype=np.uint8)
        counts = rng.integers(1, 6, size=n).astype(np.int64)
        flat = rng.integers(0, len(ACTION_TABLE), size=int(counts.sum())).astype(np.int64)
        slots = (np.arange(n) % 3 == 1).astype(np.uint8)  # every third decision a league seat's

        class Block:
            pass
        b = Block()
        b.states, b.counts, b.cands, b.slots = packed, counts, flat.astype(np.int16), slots
        b.q, b.best = np.zeros(len(flat), np.float32), np.zeros(n, np.int64)
        inference.score_pending(current, actions, torch.device("cpu"), [b], [(0, 0, n, len(flat))], [old])
        q_cur, best_cur = score_arrays(current, actions, torch.device("cpu"), packed.copy(), counts, flat)
        q_old, best_old = score_arrays(old, actions, torch.device("cpu"), packed.copy(), counts, flat)
        starts = np.cumsum(counts) - counts
        for i in range(n):
            span = slice(starts[i], starts[i] + counts[i])
            want_q, want_best = (q_old, best_old) if slots[i] else (q_cur, best_cur)
            self.assertTrue(np.allclose(b.q[span], want_q[span], atol=1e-5))
            self.assertEqual(want_best[i], b.best[i])

    def test_the_league_draws_at_most_league_models_and_anew_on_a_new_snapshot(self):
        config = small()
        with tempfile.TemporaryDirectory() as tmp:
            for i in range(6):
                snapshot(config, tmp, 1000 * (i + 1), i)
            size = _Count(0)
            league = inference.League(Path(tmp) / SNAPSHOTS, 4, size, torch.device("cpu"), seed=3)
            self.assertEqual(4, len(league.refresh(now=100.0)))
            self.assertEqual(4, size.value)
            first = list(league.files)
            self.assertIs(league.models, league.refresh(now=101.0))  # no look before LEAGUE_LOOK_SECONDS
            snapshot(config, tmp, 7000, 7)
            league.refresh(now=100.0 + inference.LEAGUE_LOOK_SECONDS + 1)
            self.assertEqual(4, len(league.models))
            self.assertEqual(7, len(league.seen))  # drawn anew from all seven
            self.assertTrue(set(league.files) <= set(league.seen))
            self.assertEqual(4, len(set(first)))

    def test_remote_league_spil_play_and_only_the_current_nets_seats_give_samples(self):
        config = small(actor_games=4, actor_device="cpu", partner_share=0.0, league_share=1.0, league_models=2)
        model = build(config).eval()
        with tempfile.TemporaryDirectory() as tmp:
            snapshot(config, tmp, 1000, 11)
            ctx = mp.get_context("spawn")
            version, lock, stop, requests = ctx.Value("q", 0), ctx.Lock(), ctx.Event(), ctx.Queue()
            done, size = ctx.Semaphore(0), ctx.Value("i", 0)
            block = shared_memory.SharedMemory(create=True, size=inference.buffer_size(512, 8192))
            thread = threading.Thread(target=inference.serve, daemon=True,
                                      args=(config, model, version, lock, requests, [(block.name, 512, 8192)],
                                            [done], stop, {}, str(Path(tmp) / SNAPSHOTS), size))
            thread.start()
            try:
                spec = inference.ClientSpec(0, block.name, requests, done, 512, 8192, league=size)
                for _ in range(100):
                    if size.value:
                        break
                    threading.Event().wait(0.05)
                self.assertEqual(1, size.value)
                stub = NetStub(False, model.points_scale, size)
                games = BatchedGames(stub, None, random.Random(4), config, factory("svaer"), STANDARD,
                                     scorer=inference.RemoteScorer(spec, stop))
                league_batch = Batch()
                while league_batch.spil < 3:
                    games.step(league_batch)
                plain = BatchedGames(stub, None, random.Random(4), small(actor_games=4, partner_share=0.0),
                                     factory("svaer"), STANDARD, scorer=inference.RemoteScorer(spec, stop))
                plain_batch = Batch()
                while plain_batch.spil < 3:
                    plain.step(plain_batch)
                # 1-3 of the four seats are the old snapshot's: fewer samples per runde
                self.assertLess(len(league_batch.actions) / league_batch.runder,
                                0.9 * len(plain_batch.actions) / plain_batch.runder)
            finally:
                stop.set()
                thread.join(timeout=10)
                block.close()
                block.unlink()

    def test_a_run_with_the_league(self):
        with tempfile.TemporaryDirectory() as tmp:
            config = small(actors=1, actor_inference="server", actor_device="cpu", actor_games=3, min_replay=600,
                           league_share=0.5, partner_share=0.0, weights_every=2)
            snapshot(config, Path(tmp) / "run", 1, 2)  # an earlier snapshot for the league to draw
            trainer = train(config, Path(tmp) / "run", max_steps=3, echo=lambda *_: None)
            self.assertEqual(3, trainer.counters["steps"])


if __name__ == "__main__":
    unittest.main()
