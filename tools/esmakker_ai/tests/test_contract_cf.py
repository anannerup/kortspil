"""The contract head's counterfactual rows (search.py, config contract_cf):
the seat made melder, a row per trump and world at every seat's first bid
of a net-only runde, and nothing else changes. CPU only, small nets.
Skipped when PyTorch is not installed."""

import importlib.util
import multiprocessing as mp
import random
import threading
import unittest
from collections import Counter
from multiprocessing import shared_memory

HAVE_TORCH = importlib.util.find_spec("torch") is not None and importlib.util.find_spec("numpy") is not None

if HAVE_TORCH:
    import numpy as np
    import torch

    from esmakker_ai import actions as A
    from esmakker_ai import features as F
    from esmakker_ai import inference
    from esmakker_ai.actor import Batch, NetStub
    from esmakker_ai.agent import CONTRACT_SIDE, CONTRACT_TRUMP
    from esmakker_ai.engine import BIDDING, CHOOSING_TRUMP, Round
    from esmakker_ai.net import build, unpack
    from esmakker_ai.partners import factory
    from esmakker_ai.rules import STANDARD
    from esmakker_ai.search import SearchingGames, won_melding
    from esmakker_ai.selfplay import random_deal
    from tests.test_training import small

WORLDS = 2


def cf_config(**changes):
    settings = dict(contract=True, contract_cf=True, contract_cf_worlds=WORLDS, actor_games=4, partner_share=0.0,
                    bid_by_partner=0.0, search_share=0.0, search_share_bid=0.0, no_sol=True)
    settings.update(changes)
    return small(**settings)


def is_cf_row(row):
    state, action, t, weight = row
    bits = unpack(np.frombuffer(state, np.uint8))
    return weight == (0.0, 0.0) and bits[F.PHASE + F.PHASE_INDEX[BIDDING]] == 1


def one_by_one(model):
    """A scorer that scores each request in a pass of its own."""
    from esmakker_ai.actor import LocalScorer
    local = LocalScorer(model, torch.device("cpu"))

    def score(states, cands):
        parts = [local([s], [c]) for s, c in zip(states, cands)]
        return np.concatenate([q for q, _ in parts]), np.concatenate([b for _, b in parts])
    return score


def play(config, steps, seed=7, scorer=None, model=None, rollouts=None, seats=None):
    model = model if model is not None else build(config).eval()
    batch = Batch()
    remote = isinstance(scorer, inference.RemoteScorer)
    games = SearchingGames(NetStub(config.no_sol, model.points_scale) if remote else model,
                           None if remote else torch.device("cpu"), random.Random(seed), config,
                           factory("svaer"), STANDARD, scorer=scorer, rollouts=rollouts)
    if seats is not None:  # who got them: (the runde, the seat) of each
        made = games._counterfactual

        def spy(game, batch):
            before = games.stats.get("cf", 0)
            made(game, batch)
            if games.stats.get("cf", 0) > before:
                seats.append(game.request[3][:2])  # (the Round itself, kept alive: its id stays its own)
        games._counterfactual = spy
    for _ in range(steps):
        games.step(batch)
    return batch, games


@unittest.skipUnless(HAVE_TORCH, "PyTorch not installed (pip install -r requirements-train.txt)")
class CounterfactualTest(unittest.TestCase):
    def test_the_seat_is_made_melder(self):
        for seed in range(12):
            r = Round(random_deal(random.Random(seed)), seed % 4, STANDARD)
            seat = r.to_act()
            self.assertTrue(won_melding(r, seat))
            self.assertEqual(CHOOSING_TRUMP, r.phase)
            self.assertEqual(seat, r.melder)

    def test_every_seat_gets_a_row_per_trump_and_world_at_its_first_bid(self):
        seats = []
        batch, games = play(cf_config(), 400, seats=seats)
        rows = [row for row in batch.search_rows if is_cf_row(row)]
        self.assertGreater(games.stats.get("cf", 0), 8)
        # rows come when all of a job's rollouts are in; some are still out after the last step
        self.assertLessEqual(len(rows), games.stats["cf_rollouts"])
        per_state = Counter(row[0] for row in rows)
        self.assertEqual({5 * WORLDS}, set(per_state.values()))  # 5 trumps x the worlds
        for state, action, t, _ in rows:
            self.assertTrue(A.TRUMP <= action < A.ACE)
            self.assertEqual(float(action - A.TRUMP), t[CONTRACT_TRUMP])
            self.assertTrue(0 <= t[CONTRACT_SIDE] <= 13)
        by_state = {}
        for state, action, _, _ in rows:
            by_state.setdefault(state, Counter())[action] += 1
        self.assertTrue(all(c == Counter({A.TRUMP + t: WORLDS for t in range(5)}) for c in by_state.values()))
        # once per seat and runde, and in most runder all four seats (a seat bids only if the runde reaches it)
        keys = [(id(r), seat) for r, seat in seats]
        self.assertEqual(len(keys), len(set(keys)))
        per_runde = Counter(r for r, _ in keys)
        self.assertEqual(4, max(per_runde.values()))
        self.assertEqual({0, 1, 2, 3}, {seat for _, seat in seats})

    def test_off_or_on_the_rest_is_the_same(self):
        searching = dict(search_share=0.1, search_share_bid=0.5, search_worlds=2, search_gumbel_k=3,
                         search_gumbel_k_play=3)
        # each request scored alone: a forward pass's floats depend on what else is in the batch
        model = build(cf_config()).eval()
        alone = one_by_one(model)
        off, _ = play(cf_config(contract_cf=False, **searching), 300, model=model, scorer=alone)
        on, _ = play(cf_config(**searching), 300, model=model, scorer=alone)
        self.assertGreater(len(on.search_rows), len(off.search_rows))
        self.assertEqual(off.states, on.states)
        self.assertEqual(off.actions, on.actions)
        self.assertEqual(off.targets, on.targets)
        self.assertEqual(off.search_rows, [row for row in on.search_rows if not is_cf_row(row)])

    def test_not_at_a_table_with_svaer(self):
        batch, games = play(cf_config(partner_share=1.0), 300)
        self.assertEqual(0, games.stats.get("cf", 0))
        self.assertFalse(any(is_cf_row(row) for row in batch.search_rows))

    def test_the_tensor_rollouts_give_the_same_rows(self):
        from esmakker_ai.trollout import Rollouts
        model = build(cf_config()).eval()
        cpu, _ = play(cf_config(), 200, model=model)
        tensor, games = play(cf_config(search_gpu_rollouts=True, search_gpu_batch=8), 200, model=model,
                             rollouts=Rollouts(model, torch.device("cpu")).points_arrays)
        self.assertGreater(games.stats.get("gpu_rollouts", 0), 0)

        def by_state(batch):
            out = {}
            for state, action, t, _ in (r for r in batch.search_rows if is_cf_row(r)):
                out.setdefault(state, []).append((action, t))
            return {s: sorted(v) for s, v in out.items()}
        a, b = by_state(cpu), by_state(tensor)
        common = set(a) & set(b)  # the jobs done in both (the GPU's wait for a batch moves when they end)
        self.assertGreater(len(common), 3)
        self.assertEqual({s: a[s] for s in common}, {s: b[s] for s in common})

    def test_the_server_gives_the_same_rows(self):
        config = cf_config(actor_device="cpu")
        model = build(config).eval()
        ctx = mp.get_context("spawn")
        version, lock, stop, requests = ctx.Value("q", 0), ctx.Lock(), ctx.Event(), ctx.Queue()
        dones = [ctx.Semaphore(0)]
        block = shared_memory.SharedMemory(create=True, size=inference.buffer_size(512, 8192))
        thread = threading.Thread(target=inference.serve, daemon=True,
                                  args=(config, model, version, lock, requests, [(block.name, 512, 8192)], dones,
                                        stop, {}))
        thread.start()

        def close():
            stop.set()
            thread.join(timeout=10)
            block.close()
            block.unlink()
        self.addCleanup(close)
        spec = inference.ClientSpec(0, block.name, requests, dones[0], 512, 8192)
        local, _ = play(config, 150, model=model)
        remote, games = play(config, 150, scorer=inference.RemoteScorer(spec, stop), model=model)
        self.assertGreater(games.stats.get("cf", 0), 0)
        for x, y in zip(local.arrays(), remote.arrays()):
            self.assertEqual(x.shape, y.shape)
            self.assertTrue((x == y).all())


if __name__ == "__main__":
    unittest.main()
