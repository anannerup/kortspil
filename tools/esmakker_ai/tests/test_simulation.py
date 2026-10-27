"""Meldinger and the declaration by simulation (search.py: bid_by_simulation,
declare_by_simulation, SimulatingPlayer), the contract guess's bias
controller (learner.py) and the melder check. CPU only, small nets.
Skipped when PyTorch is not installed."""

import importlib.util
import multiprocessing as mp
import random
import threading
import unittest
from multiprocessing import shared_memory

HAVE_TORCH = importlib.util.find_spec("torch") is not None and importlib.util.find_spec("numpy") is not None

if HAVE_TORCH:
    import numpy as np
    import torch

    from esmakker_ai import actions as A
    from esmakker_ai import inference
    from esmakker_ai import meldinger as M
    from esmakker_ai.actor import Batch, NetStub
    from esmakker_ai.agent import CONTRACT_SIDE, CONTRACT_TRUMP, TARGETS
    from esmakker_ai.engine import BIDDING, Round
    from esmakker_ai.learner import Trainer
    from esmakker_ai.net import CONTRACT_STIK, CONTRACT_TRUMPS, build, contract_bid_values, score_one, unpack
    from esmakker_ai.partners import factory
    from esmakker_ai.rules import STANDARD
    from esmakker_ai.search import SearchingGames, SimulatingPlayer, bid_options, is_declaration
    from esmakker_ai.selfplay import random_deal
    from esmakker_ai import features as F
    from tests.test_training import small

WORLDS = 2


def sim_config(**changes):
    settings = dict(contract=True, bid_by_simulation=True, bid_sim_worlds=WORLDS, actor_games=4, partner_share=0.0,
                    bid_by_partner=0.0, search_share=0.0, search_share_bid=0.0, no_sol=True)
    settings.update(changes)
    return small(**settings)


def play(config, steps, seed=7, scorer=None, model=None, spy=None):
    model = model if model is not None else build(config).eval()
    batch = Batch()
    remote = isinstance(scorer, inference.RemoteScorer)
    games = SearchingGames(NetStub(config.no_sol, model.points_scale) if remote else model,
                           None if remote else torch.device("cpu"), random.Random(seed), config,
                           factory("svaer"), STANDARD, scorer=scorer)
    if spy is not None:  # (phase, kind, candidates, searched?) of every real decision that reached _search
        search = games._search

        def watched(game, values, batch):
            _, _, cands, (r, seat, kind, *_rest) = game.request
            phase = r.phase
            out = search(game, values, batch)
            spy.append((phase, kind, len(cands), out, is_declaration(r, seat, kind, cands)))
            return out
        games._search = watched
    for _ in range(steps):
        games.step(batch)
    return batch, games


@unittest.skipUnless(HAVE_TORCH, "PyTorch not installed (pip install -r requirements-train.txt)")
class OptionsTest(unittest.TestCase):
    def test_pas_and_the_meldinger_of_the_next_numbers(self):
        r = Round(random_deal(random.Random(3)), 0, STANDARD)
        cands = [a for a in r.legal_actions(r.to_act()) if not (a < A.PAS and M.is_sol(a - A.BID))]
        options = bid_options(cands, 2)
        self.assertIn(A.PAS, options)
        numbers = {M.number(a - A.BID) for a in options if a < A.PAS}
        self.assertEqual({8, 9}, numbers)
        eights = [a for a in cands if a < A.PAS and M.number(a - A.BID) == 8]
        self.assertTrue(set(eights) <= set(options))  # every pahÃ¦ng of them
        self.assertEqual({8}, {M.number(a - A.BID) for a in bid_options(cands, 1) if a < A.PAS})


@unittest.skipUnless(HAVE_TORCH, "PyTorch not installed (pip install -r requirements-train.txt)")
class BidBySimulationTest(unittest.TestCase):
    def test_the_net_bids_only_by_its_contract_guess(self):
        model = build(sim_config()).eval()
        self.assertEqual(1.0, model.contract_mix)  # inside the simulations: the guess decides the bids
        r = Round(random_deal(random.Random(5)), 0, STANDARD)
        seat = r.to_act()
        cands = [a for a in r.legal_actions(seat) if a < A.PAS and not M.is_sol(a - A.BID)][:6]
        s = torch.from_numpy(unpack(np.frombuffer(F.to_bytes(F.encode(r, seat, 0, None)), np.uint8))[None])
        q, h = score_one(model, s, cands)
        with torch.inference_mode():
            values = contract_bid_values(model.contract_logits(h))[0] / model.points_scale
        self.assertTrue(torch.allclose(q, values[[a - A.BID for a in cands]], atol=1e-6))

    def test_every_bid_is_simulated(self):
        seen = []
        batch, games = play(sim_config(), 300, spy=seen)
        bids = [s for s in seen if s[0] == BIDDING and s[2] > 1]
        self.assertGreater(len(bids), 20)
        self.assertTrue(all(s[3] for s in bids))  # searched, never the net's own choice
        self.assertGreater(games.stats.get("simulated_bid", 0), 20)
        self.assertGreater(len(batch.search_rows), 0)
        # nothing else is searched without the shares
        self.assertTrue(all(not s[3] for s in seen if s[0] != BIDDING))

    def test_the_declaration_too(self):
        seen = []
        _, games = play(sim_config(declare_by_simulation=True), 400, spy=seen)
        declarations = [s for s in seen if s[4] and s[2] > 1]
        self.assertGreater(len(declarations), 3)
        self.assertTrue(all(s[3] for s in declarations))
        self.assertGreater(games.stats.get("simulated_declare", 0), 3)

    def test_the_server_plays_the_same(self):
        config = sim_config(actor_device="cpu")
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
        local, _ = play(config, 120, model=model)
        remote, games = play(config, 120, scorer=inference.RemoteScorer(spec, stop), model=model)
        self.assertGreater(games.stats.get("simulated_bid", 0), 0)
        for x, y in zip(local.arrays(), remote.arrays()):
            self.assertEqual(x.shape, y.shape)
            self.assertTrue(np.allclose(x, y, atol=1e-5))

    def test_off_nothing_changes(self):
        searching = dict(search_share=0.1, search_share_bid=0.5, search_worlds=2, search_gumbel_k=3,
                         search_gumbel_k_play=3)
        model = build(sim_config(bid_by_simulation=False)).eval()
        before, _ = play(sim_config(bid_by_simulation=False, **searching), 600, model=model)
        checked, games = play(sim_config(bid_by_simulation=False, melder_check_share=1.0, **searching), 600,
                              model=model)
        for x, y in zip(before.arrays(), checked.arrays()):
            self.assertTrue((x == y).all())  # the melder check only counts
        self.assertGreater(checked.counts.get("melder_check", 0), 0)
        self.assertLessEqual(checked.counts.get("melder_check_same", 0), checked.counts["melder_check"])

    def test_a_simulating_player_picks_one_of_its_options(self):
        config = sim_config()
        model = build(config).eval()
        player = SimulatingPlayer(model, config, worlds=3, rng=random.Random(1))
        r = Round(random_deal(random.Random(9)), 0, STANDARD)
        seat = r.to_act()
        action, _, cands, _ = player.decide(r, seat)
        self.assertIn(action, bid_options(cands, config.bid_sim_numbers))
        self.assertGreater(player.last_stats.get("simulated_bid", 0), 0)


@unittest.skipUnless(HAVE_TORCH, "PyTorch not installed (pip install -r requirements-train.txt)")
class BiasControllerTest(unittest.TestCase):
    def rows(self, n, side):
        states = torch.zeros(n, F.STATE_BITS)
        t = torch.zeros(n, TARGETS)
        t[:, CONTRACT_TRUMP], t[:, CONTRACT_SIDE] = 0, side
        return states, t

    def test_too_low_raises_the_weight_and_back(self):
        trainer = Trainer(small(contract=True, contract_bias_every=1, contract_bias_max=2.0))
        logits = torch.full((32, CONTRACT_TRUMPS, CONTRACT_STIK), -20.0)
        logits[:, :, 5] = 20.0  # the guess: 5 stik
        states, t = self.rows(32, 9.0)  # the simulation: 9
        for step in range(1, 400):
            trainer.counters["steps"] = step
            trainer.contract_bias(logits, states, t)
        self.assertLess(trainer.counters["contract_bias"], -3.5)
        self.assertEqual(2.0, trainer.counters["contract_mult"])  # raised, up to the cap
        self.assertTrue(trainer.notes and trainer.notes[0]["event"] == "contract_weight")
        self.assertIn("5", trainer.contract_bias_by)
        states, t = self.rows(32, 5.0)  # now it is right
        for step in range(400, 900):
            trainer.counters["steps"] = step
            trainer.contract_bias(logits, states, t)
        self.assertEqual(1.0, trainer.counters["contract_mult"])

    def test_off_by_default(self):
        trainer = Trainer(small(contract=True))
        logits = torch.zeros(8, CONTRACT_TRUMPS, CONTRACT_STIK)
        states, t = self.rows(8, 13.0)
        for step in range(1, 300):
            trainer.counters["steps"] = step
            trainer.contract_bias(logits, states, t)
        self.assertEqual(1.0, trainer.counters.get("contract_mult", 1.0))


if __name__ == "__main__":
    unittest.main()
