"""inference_fp16: the server's net in half precision scores and rolls out
as the fp32 net does, up to fp16 rounding; with the flag off nothing
changes (the other tests). Needs CUDA."""

import importlib.util
import random
import unittest

HAVE_TORCH = importlib.util.find_spec("torch") is not None and importlib.util.find_spec("numpy") is not None

if HAVE_TORCH:
    import copy

    import numpy as np
    import torch

    from esmakker_ai import features as F
    from esmakker_ai.agent import ACTION_TABLE, NetPlayer, net_candidates, play
    from esmakker_ai.engine import Round
    from esmakker_ai.net import build, score_arrays
    from esmakker_ai.rules import STANDARD
    from esmakker_ai.selfplay import random_deal
    from tests.test_training import small

CUDA = HAVE_TORCH and torch.cuda.is_available()


def decisions(model, runder=20):
    """(packed states, counts, flat candidates) of the net's decisions in self-play."""
    net = NetPlayer(model)
    states, cands = [], []
    for i in range(runder):
        rng = random.Random(i)
        r = Round(random_deal(rng), i % 4, STANDARD)
        probe = Round(r.deal, r.dealer, r.rules)
        play(r, [net] * 4)
        for seat, action in r.log:
            if probe.complete():
                break
            c = net_candidates(model, probe, seat)
            if len(c) > 1:
                states.append(F.to_bytes(F.encode(probe, seat, 0, None)))
                cands.append(c)
            probe.apply(seat, action, check=False)
    packed = np.frombuffer(b"".join(states), np.uint8).reshape(len(states), -1).copy()
    return packed, np.array([len(c) for c in cands], np.int64), np.array([a for c in cands for a in c], np.int64)


@unittest.skipUnless(CUDA, "needs CUDA")
class HalfPrecisionTest(unittest.TestCase):
    def setUp(self):
        torch.manual_seed(0)
        self.config = small(contract=True, contract_mix=0.5)
        self.model = build(self.config).eval()
        self.dev = torch.device("cuda")
        self.m32 = copy.deepcopy(self.model).to(self.dev)
        self.m16 = copy.deepcopy(self.model).to(self.dev).half()

    def test_scores_match_fp32_up_to_rounding(self):
        packed, counts, flat = decisions(self.model)
        actions = torch.from_numpy(ACTION_TABLE).to(self.dev)
        q32, b32 = score_arrays(self.m32, actions, self.dev, packed, counts, flat)
        q16, b16 = score_arrays(self.m16, actions, self.dev, packed, counts, flat)
        self.assertEqual(q16.dtype, np.float32)
        self.assertLess(np.abs(q32 - q16).max(), 0.02)
        self.assertGreater((b32 == b16).mean(), 0.97)

    def test_rollouts_match_fp32_up_to_rounding(self):
        from esmakker_ai import tbench
        from esmakker_ai.trollout import Rollouts
        rounds, spils, offered = tbench.branches(300, 4)
        out = []
        for m in (self.m32, self.m16):
            graphs = Rollouts(m, "cuda")
            out.append(graphs.points(rounds, spils, offered))
            graphs.free()
        same = (np.abs(out[0] - out[1]).max(axis=1) < 1e-9).mean()
        self.assertGreater(same, 0.8)

    def test_the_server_builds_a_half_net_and_follows_new_weights(self):
        """The fp32 learner's weights copied into the half net (rounded)."""
        fresh = build(self.config)
        self.m16.load_state_dict(fresh.state_dict())
        for a, b in zip(self.m16.parameters(), fresh.parameters()):
            self.assertEqual(a.dtype, torch.float16)
            self.assertTrue(torch.allclose(a.float().cpu(), b, atol=1e-3, rtol=1e-3))

    def test_a_run_with_a_half_precision_server(self):
        import tempfile
        from pathlib import Path

        from esmakker_ai.learner import train
        with tempfile.TemporaryDirectory() as tmp:
            config = small(actors=1, actor_inference="server", actor_device="cuda", inference_fp16=True,
                           actor_games=4, min_replay=600, search_share=0.05, search_share_bid=0.2, search_worlds=2,
                           search_gpu_rollouts=True, weights_every=2, contract=True, contract_mix=0.5)
            trainer = train(config, Path(tmp) / "run", max_steps=4, echo=lambda *_: None)
            self.assertEqual(4, trainer.counters["steps"])
            self.assertGreater(trainer.counters["runder"], 0)


if __name__ == "__main__":
    unittest.main()
