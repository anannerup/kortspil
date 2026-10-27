"""GPU rollouts (trollout.py) play as the CPU path (tbench.cpu_rollouts:
agent.play_steps with the greedy net at every seat, scored by
net.score_requests): the same choices at every decision and the same
points, but where two candidates' Q are a float tie apart."""

import random
import unittest

try:
    import torch
except ImportError:  # pragma: no cover
    torch = None

from esmakker_ai import actions as A
from tests.test_tengine import device

TIE = 1e-4  # Q (in points / points_scale) closer than this is a float tie


@unittest.skipIf(torch is None, "PyTorch is not installed")
class TRolloutParityTest(unittest.TestCase):
    def compare(self, model, seed, count):
        from esmakker_ai import tbench, trollout
        from esmakker_ai import tengine as T
        dev = device()
        rounds, spils, offered = tbench.branches(count, seed)
        starts = [len(r.log) for r in rounds]
        gpu_rounds = [r.clone() for r in rounds]
        trace = []
        points = trollout.rollout_rounds(model, gpu_rounds, spils, dev, offered, trace)
        tbench.cpu_rollouts(model, rounds, spils, dev, offered)

        per_branch = [[] for _ in rounds]  # (slot, Q per slot, offer)
        for rows, slots, values, offers in trace:
            for row, slot, q, offer in zip(rows.tolist(), slots.tolist(), values, offers.tolist()):
                per_branch[row].append((slot, q, offer))
        same = ties = 0
        for b, r in enumerate(rounds):
            log = [a for _, a in r.log[starts[b]:]]
            p = 0
            tie = False
            for slot, q, offer in per_branch[b]:
                ref = log[p] if p < len(log) else None
                if slot == T.NO_FD_SLOT:
                    if ref is not None and A.FORDAEKT <= ref < A.ACTION_COUNT:
                        ref_slot = T.ACTION_SLOT[ref]
                    else:
                        continue
                elif offer and not (A.FORDAEKT <= ref < A.ACTION_COUNT):
                    ref_slot = T.NO_FD_SLOT
                else:
                    ref_slot = T.ACTION_SLOT[ref]
                if ref_slot == slot:
                    p += 1
                    continue
                gap = abs(float(q[slot]) - float(q[ref_slot]))
                self.assertLess(gap, TIE, f"seed {seed} branch {b}: GPU {T.SLOT_ACTION[slot]}, "
                                          f"CPU {T.SLOT_ACTION[ref_slot]}, Q gap {gap}")
                tie = True
                break
            if tie:
                ties += 1
                continue
            self.assertEqual(len(log), p, f"seed {seed} branch {b}")
            self.assertEqual([float(x) for x in r.points()], points[b].tolist())
            same += 1
        return same, ties

    def test_same_as_cpu(self):
        torch.manual_seed(5)
        from esmakker_ai.tbench import load_model
        model = load_model(None, device())
        same = ties = 0
        for seed in range(3):
            s, t = self.compare(model, seed, 400)
            same, ties = same + s, ties + t
        self.assertLessEqual(ties, (same + ties) // 100)
        self.assertGreater(same, 1100)

    @unittest.skipUnless(torch is not None and torch.cuda.is_available(), "no CUDA")
    def test_graphs_play_as_eager(self):
        """The CUDA graphs (GraphRollout, Rollouts) give the eager rollout's
        points, padded and split alike."""
        from esmakker_ai import tbench, trollout
        dev = torch.device("cuda")
        model = tbench.load_model(None, dev)
        rounds, spils, offered = tbench.branches(700, 7)
        eager = trollout.rollout_rounds(model, rounds, spils, dev, offered)
        runner = trollout.Rollouts(model, dev, smallest=256, largest=512)
        try:
            graph = runner.points(rounds, spils, offered)  # 512 + 188 padded to 256
            again = runner.points(rounds[:300], spils[:300], offered[:300])
        finally:
            runner.free()
        self.assertEqual(eager.tolist(), graph.tolist())
        self.assertEqual(eager[:300].tolist(), again.tolist())


if __name__ == "__main__":
    unittest.main()
