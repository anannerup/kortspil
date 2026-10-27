"""The contract head (net.py, config contract): its shape and the meldinger's
values priced from it, the blend into the bids' Q in every scorer, labels
only from the seat's own runder as melder, the trump rollouts of search, and
a run that trains it. CPU only, small nets. Skipped when PyTorch is not
installed."""

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
    from esmakker_ai.agent import (CONTRACT_SIDE, CONTRACT_TRUMP, NO_CONTRACT, NetPlayer, contract_label, explain,
                                   play, side_stik)
    from esmakker_ai.engine import BIDDING, CHOOSING_TRUMP, PLAYING, Round
    from esmakker_ai.learner import contract_mask, train
    from esmakker_ai.net import (CONTRACT_STIK, CONTRACT_TRUMPS, STIK_BIDS, build, contract_bid_values,
                                 contract_trumps, melding_points, score_arrays, unpack, unpack_bits)
    from esmakker_ai.partners import factory
    from esmakker_ai.rules import STANDARD
    from esmakker_ai.scoring import stik_points
    from esmakker_ai.search import SearchingGames, _side_stik
    from esmakker_ai.selfplay import random_deal
    from tests.test_training import small


def bidding_round(seed):
    """A runde at its first bid."""
    return Round(random_deal(random.Random(seed)), seed % 4, STANDARD)


@unittest.skipUnless(HAVE_TORCH, "PyTorch not installed (pip install -r requirements-train.txt)")
class ContractHeadTest(unittest.TestCase):
    def test_the_head_and_the_meldinger_values(self):
        self.assertIsNone(build(small()).contract)  # off by default: the old nets load as they were
        model = build(small(contract=True)).eval()
        h = model.encode_state(torch.zeros(3, F.STATE_BITS))
        self.assertEqual((3, CONTRACT_TRUMPS, CONTRACT_STIK), tuple(model.heads(h)["contract"].shape))
        self.assertEqual((3, STIK_BIDS), tuple(contract_bid_values(model.contract_logits(h)).shape))
        # all of the side's stik certain: 9 in hearts, 4 in every other trump
        logits = torch.full((1, CONTRACT_TRUMPS, CONTRACT_STIK), -50.0)
        logits[0, :, 4] = 50.0
        logits[0, 2, 4], logits[0, 2, 9] = -50.0, 50.0
        values = contract_bid_values(logits)[0]
        points = STANDARD.points
        side = (0, 2)
        self.assertAlmostEqual(float(stik_points(M.stik(8), side, 9, 2, points)[0]), float(values[M.stik(8)]), 4)
        self.assertAlmostEqual(float(stik_points(M.stik(9), side, 9, 2, points)[0]), float(values[M.stik(9)]), 4)
        # gode is in clubs: 4 stik there, whatever hearts would bring
        self.assertAlmostEqual(float(stik_points(M.stik(8, M.GODE), side, 4, 0, points)[0]),
                               float(values[M.stik(8, M.GODE)]), 4)
        # vip's trump is turned up: the mean over the trumps it may be, of the mean of the kitty card's factor
        vip = M.stik(10, M.VIP)
        expected = sum(w * sum(float(stik_points(vip, side, 9 if t == 2 else 4, t, points, card)[0]) for card in (1, 2, 3)) / 3
                       for t, w in enumerate(contract_trumps()[vip]))
        self.assertAlmostEqual(expected, float(values[vip]), 3)
        self.assertEqual((STIK_BIDS, CONTRACT_TRUMPS, CONTRACT_STIK), melding_points().shape)

    def test_the_blend_changes_only_the_stik_bids_and_every_scorer_agrees(self):
        plain = build(small(contract=True)).eval()
        mixed = build(small(contract=True, contract_mix=1.0)).eval()
        mixed.load_state_dict(plain.state_dict())
        actions = torch.from_numpy(__import__("esmakker_ai.agent", fromlist=["ACTION_TABLE"]).ACTION_TABLE)
        r = bidding_round(3)
        seat = r.to_act()
        cands = F.candidates(r, seat)
        state = F.to_bytes(F.encode(r, seat))
        q_plain = NetPlayer(plain).scores(state, cands)
        q_mixed = NetPlayer(mixed).scores(state, cands)
        s = torch.from_numpy(unpack(np.frombuffer(state, np.uint8))[None])
        with torch.inference_mode():
            values = contract_bid_values(mixed.contract_logits(mixed.encode_state(s)))[0] / mixed.points_scale
        for i, a in enumerate(cands):
            if a < STIK_BIDS:
                self.assertAlmostEqual(float(values[a]), float(q_mixed[i]), 5)
            else:
                self.assertAlmostEqual(float(q_plain[i]), float(q_mixed[i]), 6)  # pas, sol: the Q head alone
        # the batched scorer (the actors' and the inference server's) gives the same, also for a state in the
        # card play, where nothing is blended
        r2 = bidding_round(5)
        play(r2, [NetPlayer(plain)] * 4)
        probe = Round(r2.deal, r2.dealer, STANDARD)
        for seat2, action in r2.log:
            if probe.phase == PLAYING:
                break
            probe.apply(seat2, action, check=False)
        states = [state]
        all_cands = [cands]
        if probe.phase == PLAYING:
            seat2 = probe.to_act()
            states.append(F.to_bytes(F.encode(probe, seat2)))
            all_cands.append(F.candidates(probe, seat2))
        packed = np.frombuffer(bytearray(b"".join(states)), np.uint8).reshape(len(states), -1)
        counts = np.array([len(c) for c in all_cands], np.int64)
        flat = np.array([a for c in all_cands for a in c], np.int64)
        q, _ = score_arrays(mixed, actions, torch.device("cpu"), packed, counts, flat)
        np.testing.assert_allclose(q_mixed, q[:len(cands)], atol=1e-5)
        if len(states) > 1:
            np.testing.assert_allclose(NetPlayer(plain).scores(states[1], all_cands[1]), q[len(cands):], atol=1e-5)

    def test_a_stik_net_with_the_blend_never_melder_sol(self):
        model = build(small(no_sol=True, contract=True, contract_mix=1.0)).eval()
        for i in range(15):
            r = bidding_round(i)
            play(r, [NetPlayer(model, epsilon=0.3, rng=random.Random(i), bid_epsilon=1.0)] * 4)
            res = r.result()
            self.assertFalse(res is not None and res["kind"] == "sol")

    def test_explain_gives_the_contract_guess(self):
        model = build(small(contract=True)).eval()
        r = bidding_round(1)
        e = explain(model, r, r.to_act())
        self.assertEqual(set(range(CONTRACT_TRUMPS)), set(e["contract_stik"]))
        self.assertTrue(all(0 <= v <= 13 for v in e["contract_stik"].values()))
        self.assertIn("9", e["contract_values"])
        self.assertNotIn("contract_stik", explain(build(small()).eval(), r, r.to_act()))


@unittest.skipUnless(HAVE_TORCH, "PyTorch not installed (pip install -r requirements-train.txt)")
class ContractLabelTest(unittest.TestCase):
    def test_only_the_melder_of_a_played_stik_melding_gets_a_label(self):
        model = build(small()).eval()
        labelled = 0
        for i in range(25):
            r = bidding_round(i)
            play(r, [NetPlayer(model, epsilon=0.3, rng=random.Random(i), bid_epsilon=0.5)] * 4)
            for seat in range(4):
                label = contract_label(r, seat)
                if r.complete() and r.kind == "stik" and seat == r.melder:
                    self.assertEqual((float(r.trump), float(r.result()["stik"])), label)
                    labelled += 1
                else:
                    self.assertEqual(NO_CONTRACT, label)
        self.assertGreater(labelled, 0)

    def test_the_learner_trains_it_only_before_the_card_play(self):
        config = small(contract=True)
        model = build(config).eval()
        batch = Batch()
        rng = random.Random(4)
        while batch.runder < 20:
            play_game(model, rng, config, factory("svaer"), STANDARD, batch)
        states, _, targets, _ = batch.arrays()
        labelled = targets[:, CONTRACT_TRUMP] >= 0
        self.assertTrue(labelled.any() and not labelled.all())
        s = unpack_bits(torch.from_numpy(states))
        mask = contract_mask(s, torch.from_numpy(targets)).numpy() > 0
        self.assertTrue(mask.any())
        self.assertTrue((labelled[mask]).all())
        playing = s[:, F.PHASE + F.PHASE_INDEX[PLAYING]].numpy() > 0
        self.assertFalse((mask & playing).any())
        self.assertTrue((labelled & playing).any())  # labelled, but not trained there
        self.assertTrue(((targets[mask, CONTRACT_SIDE] >= 0) & (targets[mask, CONTRACT_SIDE] <= 13)).all())


@unittest.skipUnless(HAVE_TORCH, "PyTorch not installed (pip install -r requirements-train.txt)")
class ContractSearchTest(unittest.TestCase):
    def test_a_searched_trump_choice_gives_a_row_per_trump_and_world(self):
        config = small(contract=True, actor_games=6, search_share=0.0, search_share_bid=1.0, search_worlds=2,
                       search_gumbel_k=3, search_gumbel_k_play=5, partner_share=0.0, no_sol=True)
        model = build(config).eval()
        batch = Batch()
        games = SearchingGames(model, torch.device("cpu"), random.Random(6), config, factory("svaer"), STANDARD)
        found = False
        for _ in range(3000):
            games.step(batch)
            if any(row[3] == (0.0, 0.0) for row in batch.search_rows):
                found = True
                break
        self.assertTrue(found)
        for state, action, t, weight in batch.search_rows:
            if weight != (0.0, 0.0):
                continue
            self.assertTrue(A.TRUMP <= action < A.ACE)
            self.assertEqual(float(action - A.TRUMP), t[CONTRACT_TRUMP])
            self.assertTrue(0 <= t[CONTRACT_SIDE] <= 13)
            bits = unpack(np.frombuffer(state, np.uint8))
            self.assertEqual(1, bits[F.PHASE + F.PHASE_INDEX[CHOOSING_TRUMP]])

    def test_the_side_stik_from_the_gpu_points(self):
        model = build(small()).eval()
        checked = 0
        for i in range(30):
            r = bidding_round(i)
            players = [NetPlayer(model, epsilon=0.2, rng=random.Random(i), bid_epsilon=0.5)] * 4
            play(r, players)
            if not (r.complete() and r.kind == "stik"):
                continue
            start = Round(r.deal, r.dealer, STANDARD)
            for seat, action in r.log:
                if start.phase == PLAYING:
                    break
                start.apply(seat, action, check=False)
            self.assertEqual(side_stik(r), _side_stik(start, [float(p) for p in r.points()]))
            self.assertEqual(side_stik(r), _side_stik(r))
            checked += 1
        self.assertGreater(checked, 3)


@unittest.skipUnless(HAVE_TORCH, "PyTorch not installed (pip install -r requirements-train.txt)")
class ContractRunTest(unittest.TestCase):
    def test_server_scoring_is_the_in_process_scoring(self):
        config = small(contract=True, contract_mix=0.5, actor_games=6, actor_device="cpu", partner_share=0.3,
                       search_share=0.05, search_share_bid=0.5, search_worlds=2, search_gumbel_k=4,
                       search_gumbel_k_play=4, search_bid_pas=True, no_sol=True)
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
        local, remote = Batch(), Batch()
        a = SearchingGames(model, torch.device("cpu"), random.Random(2), config, factory("svaer"), STANDARD)
        b = SearchingGames(NetStub(config.no_sol, model.points_scale), None, random.Random(2), config,
                           factory("svaer"), STANDARD, scorer=inference.RemoteScorer(spec, stop))
        for _ in range(150):
            a.step(local)
            b.step(remote)
        self.assertGreater(remote.searched, 0)
        for x, y in zip(local.arrays(), remote.arrays()):
            self.assertEqual(x.shape, y.shape)
            self.assertTrue((x == y).all())

    def test_a_run_trains_the_contract_head(self):
        with tempfile.TemporaryDirectory() as tmp:
            config = small(contract=True, contract_mix=0.5, search_share=0.05, search_share_bid=0.5, search_worlds=2,
                           search_gumbel_k=4, search_gumbel_k_play=4, search_bid_pas=True, no_sol=True, min_replay=400)
            trainer = train(config, Path(tmp) / "run", max_steps=4, echo=lambda *_: None)
            self.assertGreaterEqual(trainer.counters["steps"], 4)
            self.assertIn("contract", trainer.last_losses)
            self.assertGreater(trainer.last_losses["contract"], 0)

    def test_a_run_with_the_inference_server(self):
        with tempfile.TemporaryDirectory() as tmp:
            config = small(contract=True, contract_mix=0.5, actors=2, actor_inference="server", actor_device="cpu",
                           actor_games=4, min_replay=600, search_share=0.05, search_share_bid=0.3, search_worlds=2,
                           search_gumbel_k=4, search_gumbel_k_play=4, search_gpu_rollouts=True, no_sol=True,
                           weights_every=2)
            trainer = train(config, Path(tmp) / "run", max_steps=4, echo=lambda *_: None)
            self.assertEqual(4, trainer.counters["steps"])
            self.assertIn("contract", trainer.last_losses)


if __name__ == "__main__":
    unittest.main()
