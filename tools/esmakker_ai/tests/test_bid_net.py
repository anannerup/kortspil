"""The bid net (config bid_net): a net of its own beside the play net,
used for every bid the net makes, learning only from the contract rows, and
saved, served and warm-started with the play net; plus the melder check
that tries every seat at the same contract. CPU only, small nets. Skipped
when PyTorch is not installed."""

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

    from esmakker_ai import actions as A
    from esmakker_ai import features as F
    from esmakker_ai import inference
    from esmakker_ai import meldinger as M
    from esmakker_ai.actor import Batch, NetStub, play_game
    from esmakker_ai.agent import ACTION_TABLE, CONTRACT_TRUMP, explain
    from esmakker_ai.engine import BIDDING, Round
    from esmakker_ai.learner import Trainer, train, warm_start
    from esmakker_ai.net import contract_bid_values, build, score_one, unpack
    from esmakker_ai.partners import factory
    from esmakker_ai.rules import STANDARD
    from esmakker_ai.search import SearchingGames
    from esmakker_ai.selfplay import random_deal
    from tests.test_training import small


def bid_config(**changes):
    settings = dict(bid_net=True, bid_hidden=32, bid_layers=2, contract_cf=True, contract_cf_worlds=2, actor_games=4,
                    partner_share=0.0, bid_by_partner=0.0, search_share=0.0, search_share_bid=0.0, no_sol=True)
    settings.update(changes)
    return small(**settings)


def bidding_state():
    r = Round(random_deal(random.Random(5)), 0, STANDARD)
    seat = r.to_act()
    cands = [a for a in r.legal_actions(seat) if a < A.PAS and not M.is_sol(a - A.BID)][:6]
    s = torch.from_numpy(unpack(np.frombuffer(F.to_bytes(F.encode(r, seat, 0, None)), np.uint8))[None])
    return r, seat, cands, s


def play(config, steps, seed=7, scorer=None, model=None):
    model = model if model is not None else build(config).eval()
    batch = Batch()
    remote = isinstance(scorer, inference.RemoteScorer)
    games = SearchingGames(NetStub(config.no_sol, model.points_scale) if remote else model,
                           None if remote else torch.device("cpu"), random.Random(seed), config,
                           factory("svaer"), STANDARD, scorer=scorer)
    for _ in range(steps):
        games.step(batch)
    return batch, games


@unittest.skipUnless(HAVE_TORCH, "PyTorch not installed (pip install -r requirements-train.txt)")
class TwoNetsTest(unittest.TestCase):
    def test_off_the_net_is_as_before(self):
        model = build(small(contract=True))
        self.assertIsNone(model.bid)
        self.assertIsNotNone(model.contract)
        self.assertEqual([id(p) for p in model.parameters()], [id(p) for p in model.play_parameters()])
        self.assertIsNone(Trainer(small(contract=True)).bid_optimizer)

    def test_on_the_play_net_has_no_contract_head_and_shares_nothing(self):
        model = build(bid_config())
        self.assertIsNone(model.contract)
        self.assertIsNotNone(model.bid)
        self.assertTrue(model.has_contract)
        play = {id(p) for p in model.play_parameters()}
        self.assertFalse(play & {id(p) for p in model.bid.parameters()})
        self.assertEqual(len(list(model.parameters())), len(play) + len(list(model.bid.parameters())))

    def test_the_bids_are_the_bid_nets_guess(self):
        model = build(bid_config()).eval()
        self.assertEqual(1.0, model.contract_mix)
        _, _, cands, s = bidding_state()
        q, _ = score_one(model, s, cands)
        with torch.inference_mode():
            values = contract_bid_values(model.bid(s))[0] / model.points_scale
        self.assertTrue(torch.allclose(q, values[[a - A.BID for a in cands]], atol=1e-6))
        # the play net's weights do not move a bid; the bid net's do
        with torch.no_grad():
            for p in model.play_parameters():
                p.add_(0.5)
        self.assertTrue(torch.allclose(q, score_one(model, s, cands)[0], atol=1e-6))
        with torch.no_grad():
            model.bid.out.bias.add_(torch.linspace(-2, 2, model.bid.out.bias.numel()))
        self.assertFalse(torch.allclose(q, score_one(model, s, cands)[0], atol=1e-4))

    def test_explain_reads_the_bid_net(self):
        model = build(bid_config()).eval()
        r, seat, _, _ = bidding_state()
        e = explain(model, r, seat)
        self.assertEqual(5, len(e["contract_stik"]))
        self.assertAlmostEqual(1.0, sum(e["contract_dist"][0]), places=4)

    def test_only_the_bid_net_learns_from_the_contract_rows(self):
        trainer = Trainer(bid_config())
        batch = Batch()
        rng = random.Random(4)
        while batch.runder < 30:
            play_game(trainer.cpu_copy(), rng, trainer.config, factory("svaer"), STANDARD, batch)
        states, actions, targets, weights = batch.arrays()
        self.assertTrue((targets[:, CONTRACT_TRUMP] >= 0).any())  # the real melders' outcomes are there
        trainer.add(states, actions, targets, batch.runder, batch.spil, weights)
        from esmakker_ai.net import unpack_bits
        s = unpack_bits(torch.from_numpy(states[:256]))
        t = torch.from_numpy(targets[:256])
        _, heads = trainer.model(s, trainer.action_table[torch.from_numpy(actions[:256].astype(np.int64))])
        loss = trainer.contract_loss(heads["contract"], s, t)
        self.assertGreater(float(loss.detach()), 0)
        loss.backward()
        self.assertTrue(all(p.grad is None for p in trainer.model.play_parameters()))
        self.assertTrue(any(p.grad is not None and p.grad.abs().sum() > 0 for p in trainer.model.bid.parameters()))
        trainer.model.zero_grad(set_to_none=True)
        before = [p.detach().clone() for p in trainer.model.bid.parameters()]
        trainer.train_step()
        self.assertIn("contract", trainer.last_losses)
        self.assertTrue(any(not torch.equal(a, b) for a, b in zip(before, trainer.model.bid.parameters())))

    def test_a_checkpoint_keeps_both_nets_and_both_optimizers(self):
        with tempfile.TemporaryDirectory() as tmp:
            config = bid_config(min_replay=200)
            trainer = Trainer(config)
            while trainer.counters["steps"] < 3:
                trainer.sync_round()
            path = Path(tmp) / "checkpoint.pt"
            trainer.save(path)
            again = Trainer(config)
            again.load(path)
            for (name, a), b in zip(trainer.model.state_dict().items(), again.model.state_dict().values()):
                self.assertTrue(torch.equal(a, b), name)
            self.assertEqual(trainer.bid_optimizer.state_dict()["state"].keys(),
                             again.bid_optimizer.state_dict()["state"].keys())

    def test_a_warm_start_copies_the_play_net_and_a_fresh_bid_net(self):
        with tempfile.TemporaryDirectory() as tmp:
            old = Trainer(small(contract=True))
            path = Path(tmp) / "old.pt"
            old.save(path)
            torch.manual_seed(9)
            model = build(bid_config())
            fresh = {k: v.clone() for k, v in model.state_dict().items() if k.startswith("bid.")}
            warm_start(model, path)
            new = model.state_dict()
            for name, value in old.model.state_dict().items():
                if not name.startswith("contract."):
                    self.assertTrue(torch.equal(value, new[name]), name)
            for name, value in fresh.items():
                self.assertTrue(torch.equal(value, new[name]), name)

    def test_a_run_trains_both(self):
        with tempfile.TemporaryDirectory() as tmp:
            config = bid_config(search_share=0.05, search_share_bid=0.5, search_worlds=2, search_gumbel_k=4,
                                search_gumbel_k_play=4, min_replay=400, bid_by_simulation=True, bid_sim_worlds=2,
                                bid_sim_share=0.5, declare_by_simulation=True)
            trainer = train(config, Path(tmp) / "run", max_steps=4, echo=lambda *_: None)
            self.assertGreaterEqual(trainer.counters["steps"], 4)
            self.assertGreater(trainer.last_losses["contract"], 0)

    def test_the_server_plays_the_same(self):
        config = bid_config(actor_device="cpu", bid_by_simulation=True, bid_sim_worlds=2)
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
        self.assertGreater(games.stats.get("cf", 0), 0)
        for x, y in zip(local.arrays(), remote.arrays()):
            self.assertEqual(x.shape, y.shape)
            self.assertTrue(np.allclose(x, y))


@unittest.skipUnless(HAVE_TORCH, "PyTorch not installed (pip install -r requirements-train.txt)")
class MelderCheckTest(unittest.TestCase):
    def test_every_seat_is_tried_at_the_same_contract(self):
        config = bid_config(melder_check_share=1.0, contract_cf=False)
        model = build(config).eval()
        games = SearchingGames(model, torch.device("cpu"), random.Random(3), config, factory("svaer"), STANDARD)
        tried = []
        keep = games._keep

        def spy(ro):
            if ro[0].check is not None and ro[2].phase != BIDDING:
                tried.append((id(ro[0]), ro[2].melder, ro[2].melding))
            keep(ro)
        games._keep = spy
        batch = Batch()
        for _ in range(400):
            games.step(batch)
        self.assertGreater(len(tried), 10)
        self.assertGreater(batch.counts.get("melder_check", 0), 0)
        self.assertIn("melder_check_real", batch.counts)
        by_job = {}
        for job, melder, melding in tried:
            by_job.setdefault(job, set()).add((melder, melding))
        meldinger = {m for pairs in by_job.values() for _, m in pairs}
        self.assertEqual(1, len(meldinger))  # the lowest plain melding, for every seat
        self.assertTrue(any(len({s for s, _ in pairs}) == 4 for pairs in by_job.values()))


if __name__ == "__main__":
    unittest.main()
