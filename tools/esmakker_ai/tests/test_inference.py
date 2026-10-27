"""The inference server (inference.py, actor_inference "server"): the actors
import no torch, their samples are the in-process path's, and a run trains
with it. CPU only, small nets. Skipped when PyTorch is not installed."""

import importlib.util
import multiprocessing as mp
import random
import subprocess
import sys
import tempfile
import threading
import unittest
from multiprocessing import shared_memory
from pathlib import Path

HAVE_TORCH = importlib.util.find_spec("torch") is not None and importlib.util.find_spec("numpy") is not None
TOOL_DIR = Path(__file__).resolve().parent.parent

if HAVE_TORCH:
    import torch

    from esmakker_ai import inference
    from esmakker_ai.actor import Batch, BatchedGames, NetStub
    from esmakker_ai.learner import CHECKPOINT, load_weights, train
    from esmakker_ai.net import build
    from esmakker_ai.partners import factory
    from esmakker_ai.rules import STANDARD
    from esmakker_ai.search import SearchingGames
    from tests.test_training import small


class TorchFreeTest(unittest.TestCase):
    def test_the_actor_side_imports_no_torch(self):
        code = ("import sys; import esmakker_ai.actor, esmakker_ai.agent, esmakker_ai.search, esmakker_ai.inference, "
                "esmakker_ai.svaer, esmakker_ai.partners, esmakker_ai.train, esmakker_ai.tbranch; print('torch' in sys.modules)")
        out = subprocess.run([sys.executable, "-c", code], cwd=TOOL_DIR, capture_output=True, text=True, check=True)
        self.assertEqual("False", out.stdout.strip())


@unittest.skipUnless(HAVE_TORCH, "PyTorch not installed (pip install -r requirements-train.txt)")
class ServerTest(unittest.TestCase):
    def serve(self, config, model, actors):
        """A server in a thread on the CPU; returns (specs, stop)."""
        ctx = mp.get_context("spawn")
        version, lock, stop, requests = ctx.Value("q", 0), ctx.Lock(), ctx.Event(), ctx.Queue()
        dones = [ctx.Semaphore(0) for _ in range(actors)]
        blocks = [shared_memory.SharedMemory(create=True, size=inference.buffer_size(512, 8192)) for _ in range(actors)]
        names = [(b.name, 512, 8192) for b in blocks]
        thread = threading.Thread(target=inference.serve, daemon=True,
                                  args=(config, model, version, lock, requests, names, dones, stop, {}))
        thread.start()

        def close():
            stop.set()
            thread.join(timeout=10)
            for b in blocks:
                b.close()
                b.unlink()
        self.addCleanup(close)
        return [inference.ClientSpec(i, b.name, requests, dones[i], 512, 8192) for i, b in enumerate(blocks)], stop

    def test_remote_samples_are_the_in_process_samples(self):
        config = small(actor_games=6, actor_device="cpu", partner_share=0.5, search_share=0.05, search_share_bid=0.3,
                       search_worlds=2, search_gumbel_k=4, search_belief=2, no_sol=True)
        model = build(config).eval()
        specs, stop = self.serve(config, model, 1)
        local, remote = Batch(), Batch()
        a = SearchingGames(model, torch.device("cpu"), random.Random(2), config, factory("svaer"), STANDARD)
        b = SearchingGames(NetStub(config.no_sol, model.points_scale), None, random.Random(2), config,
                           factory("svaer"), STANDARD, scorer=inference.RemoteScorer(specs[0], stop))
        for _ in range(150):
            a.step(local)
            b.step(remote)
        self.assertGreater(remote.searched, 0)
        self.assertGreater(len(remote), 50)
        for x, y in zip(local.arrays(), remote.arrays()):
            self.assertEqual(x.shape, y.shape)
            self.assertTrue((x == y).all())

    def test_a_request_larger_than_the_block_is_split(self):
        config = small(actor_games=4, actor_device="cpu")
        model = build(config).eval()
        specs, stop = self.serve(config, model, 1)
        scorer = inference.RemoteScorer(specs[0], stop)
        scorer.max_states = 3  # BatchedGames scores 4 decisions at once
        local, remote = Batch(), Batch()
        a = BatchedGames(model, torch.device("cpu"), random.Random(3), config, factory("svaer"), STANDARD)
        b = BatchedGames(NetStub(False, model.points_scale), None, random.Random(3), config, factory("svaer"),
                         STANDARD, scorer=scorer)
        while local.spil < 2:
            a.step(local)
            b.step(remote)
        for x, y in zip(local.arrays(), remote.arrays()):
            self.assertTrue((x == y).all())

    def test_a_run_with_the_inference_server(self):
        with tempfile.TemporaryDirectory() as tmp:
            config = small(actors=2, actor_inference="server", actor_device="cpu", actor_games=4, min_replay=600,
                           weights_every=2)
            trainer = train(config, Path(tmp) / "run", max_steps=5, echo=lambda *_: None)
            self.assertEqual(5, trainer.counters["steps"])
            self.assertGreater(trainer.counters["runder"], 0)
            _, saved = load_weights(Path(tmp) / "run" / CHECKPOINT)
            self.assertEqual(5, saved["counters"]["steps"])


if __name__ == "__main__":
    unittest.main()
