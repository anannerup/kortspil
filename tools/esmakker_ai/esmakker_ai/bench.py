"""Rough speed of the engine for self-play.

    python -m esmakker_ai.bench [runder] [seed]

"raw" picks random legal actions straight from the engine (the engine's
own cost); the bots act on a full observation dict per decision
(observation.py), which costs several times more.
"""

import random
import sys
import time

from . import actions as A
from . import cards as C
from .bots import FirstBot, RandomBot
from .engine import BANKING, Round
from .selfplay import play_runde, random_deal


def bench_raw(runder, seed):
    rng = random.Random(seed)
    steps = 0
    started = time.perf_counter()
    for index in range(runder):
        r = Round(random_deal(rng), index % 4)
        while not r.over():
            if r.phase == BANKING:
                r.apply(r.melder, A.BANKSLUT, check=False)
                continue
            seat = r.to_act()
            size = r.discard_size(seat)
            action = tuple(rng.sample(C.cards_of(r.hand(seat)), size)) if size else rng.choice(r.legal_actions(seat))
            r.apply(seat, action, check=False)
        steps += len(r.log)
    elapsed = time.perf_counter() - started
    return runder / elapsed, steps / elapsed


def bench(bot_class, runder, seed, check):
    rng = random.Random(seed)
    bots = [bot_class(seed * 4 + seat) for seat in range(4)]
    steps = 0
    started = time.perf_counter()
    for index in range(runder):
        r = play_runde(Round(random_deal(rng), index % 4), bots, check=check)
        steps += len(r.log)
    elapsed = time.perf_counter() - started
    return runder / elapsed, steps / elapsed


def main(argv):
    runder = int(argv[1]) if len(argv) > 1 else 2000
    seed = int(argv[2]) if len(argv) > 2 else 1
    per_s, steps_s = bench_raw(runder, seed)
    print(f"{'raw':9} check=False  {per_s:7.0f} runder/s  {steps_s:9.0f} actions/s")
    for bot_class in (FirstBot, RandomBot):
        for check in (True, False):
            per_s, steps_s = bench(bot_class, runder, seed, check)
            print(f"{bot_class.__name__:9} check={check!s:5}  {per_s:7.0f} runder/s  {steps_s:9.0f} actions/s")


if __name__ == "__main__":
    main(sys.argv)
