"""tfeatures.encode gives exactly features.encode's bits: every step of
random stik runder (tests/test_tengine.py's), seen from the seat to act and
from another seat, with random spil contexts (and none)."""

import random
import unittest

import numpy as np

try:
    import torch
except ImportError:  # pragma: no cover
    torch = None

from esmakker_ai import features as F
from esmakker_ai.spil import SpilContext
from tests.test_tengine import apply_python, candidates, device, random_choice, random_states


def random_spil(rng):
    if rng.random() < 0.2:
        return None
    runder = rng.randint(1, 20)
    return SpilContext(rng.randint(0, runder - 1), runder, tuple(rng.randint(-80, 80) / 2 for _ in range(4)))


def reference_bits(r, seat, spil):
    packed = np.frombuffer(F.to_bytes(F.encode(r, seat, 0, spil)), np.uint8)
    return np.unpackbits(packed, bitorder="little").astype(bool)


@unittest.skipIf(torch is None, "PyTorch is not installed")
class TFeaturesParityTest(unittest.TestCase):
    def test_every_step(self):
        from esmakker_ai import tengine as T
        from esmakker_ai import tfeatures as TF
        checked = 0
        for seed in range(4):
            rng = random.Random(100 + seed)
            dev = device()
            rounds, offered = random_states(rng, 250)
            spils = [random_spil(rng) for _ in rounds]
            st = T.from_rounds(rounds, dev, offered)
            static = TF.static_rows(rounds, spils, dev)
            while True:
                rows = (~st.done).nonzero().squeeze(1)
                if not rows.numel():
                    break
                seat, mask, offer = T.decision(st, rows)
                other = (seat + torch.randint(1, 4, seat.shape, device=dev)) % 4
                for seats in (seat, other):
                    got = TF.encode(st, static, rows, seats).cpu().numpy()
                    for i, (row, s) in enumerate(zip(rows.tolist(), seats.tolist())):
                        want = reference_bits(rounds[row], s, spils[row])
                        if not np.array_equal(want, got[i]):
                            diff = np.nonzero(want != got[i])[0].tolist()
                            self.fail(f"seed {seed} row {row} seat {s}: bits {diff} differ")
                        checked += 1
                slots = []
                for row in rows.tolist():
                    r = rounds[row]
                    s, o, cands = candidates(r, offered[row])
                    action = random_choice(rng, cands)
                    offered[row] |= o
                    apply_python(r, s, action)
                    slots.append(T.ACTION_SLOT[action])
                T.apply(st, rows, seat, torch.tensor(slots, device=dev), offer)
        self.assertGreater(checked, 50_000)


if __name__ == "__main__":
    unittest.main()
