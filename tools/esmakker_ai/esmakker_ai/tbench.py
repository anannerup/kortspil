"""GPU rollouts (trollout.py) against the CPU path: the reference driver
(search.py's rollouts with the net at all four seats: agent.play_steps
generators scored together by net.score_requests, one batch per step) and
the benchmark.

    python -m esmakker_ai.tbench [--weights PATH] [--sizes 256,1024,4096]
"""

import random
import time

import numpy as np
import torch

from . import features as F
from .agent import NetPlayer, play_steps
from .net import EsmakkerNet, score_requests


def action_table(device):
    packed = np.frombuffer(b"".join(F.action_bytes(a) for a in range(F.ACTION_KINDS)), np.uint8)
    bits = np.unpackbits(packed.reshape(F.ACTION_KINDS, F.ACTION_BYTES), axis=-1, bitorder="little")
    return torch.from_numpy(bits.astype(np.float32)).to(device)


def cpu_rollouts(model, rounds, spils, device, offered=None):
    """The CPU path: each Round (changed in place) played to its end by
    agent.play_steps with the greedy net at every seat, all of them scored
    in one score_requests call per step, as SearchingGames scores its
    rollouts. Returns the Rounds."""
    greedy = NetPlayer(model, 0.0, random.Random(0))
    actions = action_table(device)
    live = []
    for i, (r, spil) in enumerate(zip(rounds, spils)):
        steps = play_steps(r, [greedy] * 4, (), spil=spil, offered=bool(offered[i]) if offered is not None else False)
        try:
            live.append([steps, next(steps)])
        except StopIteration:
            pass
    while live:
        _, best = score_requests(model, actions, device, [g[1][1] for g in live], [g[1][2] for g in live])
        still = []
        for g, b in zip(live, best):
            try:
                g[1] = g[0].send(g[1][2][b])
                still.append(g)
            except StopIteration:
                pass
        live = still
    return rounds


def load_model(weights, device):
    """A net to roll out with: `weights` warm-started (any FORMAT
    learner.warm_start reads), or a fresh net seeded 1."""
    torch.manual_seed(1)
    model = EsmakkerNet()
    if weights:
        from .learner import warm_start
        warm_start(model, weights)
    return model.to(device).eval()


def branches(count, seed):
    """`count` stik runder at their first lead or later, with spil
    contexts: random bidding and declaration (tests' random_stik_round),
    then a few random plays."""
    from tests.test_tengine import random_states
    from tests.test_tfeatures import random_spil
    rng = random.Random(seed)
    rounds, offered = random_states(rng, count, max_steps=20)
    return rounds, [random_spil(rng) for _ in rounds], offered


def bench(weights=None, sizes=(256, 1024, 4096, 16384), cpu_max=1024, seed=1):
    from . import trollout as TR
    device = torch.device("cuda")
    model = load_model(weights, device)
    base, spils, offered = branches(max(256, min(max(sizes), 1024)), seed)
    out = []
    for size in sizes:
        idx = [i % len(base) for i in range(size)]
        rounds = [base[i].clone() for i in idx]
        sp = [spils[i] for i in idx]
        off = [offered[i] for i in idx]
        torch.cuda.synchronize()
        torch.cuda.empty_cache()
        torch.cuda.reset_peak_memory_stats()
        before = torch.cuda.memory_allocated()
        t0 = time.perf_counter()
        TR.rollout_rounds(model, rounds, sp, device, off)
        torch.cuda.synchronize()
        gpu = time.perf_counter() - t0
        peak = (torch.cuda.max_memory_allocated() - before) / 2 ** 20
        row = {"branches": size, "gpu_s": round(gpu, 3), "gpu_per_s": round(size / gpu), "gpu_peak_mib": round(peak)}
        if size <= cpu_max:
            rounds = [base[i].clone() for i in idx]
            t0 = time.perf_counter()
            cpu_rollouts(model, rounds, sp, device, off)
            cpu = time.perf_counter() - t0
            row.update({"cpu_s": round(cpu, 3), "cpu_per_s": round(size / cpu), "speedup": round(cpu / gpu, 1)})
        out.append(row)
        print(row, flush=True)
    torch.cuda.empty_cache()
    return out


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(prog="python -m esmakker_ai.tbench")
    parser.add_argument("--weights")
    parser.add_argument("--sizes", default="256,1024,4096,16384")
    parser.add_argument("--cpu-max", type=int, default=1024)
    args = parser.parse_args()
    bench(args.weights, tuple(int(s) for s in args.sizes.split(",")), args.cpu_max)
