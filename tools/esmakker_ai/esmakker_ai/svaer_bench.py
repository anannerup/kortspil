"""Same hand, same seat (duplicate play): Svær against the first bot.

    python -m esmakker_ai.svaer_bench [deals] [seed] [field]

Every deal is played once per level and per seat: Svær and the first bot
each hold the very same hand from the very same seat (same kortgiver,
same rules), against the same field (three bots of the field level:
"first" or "svaer"). The measure is the seat's points per runde, Svær
minus the first bot, with a 95 % confidence interval. A redealt runde
(everybody passed) counts 0.
"""

import math
import random
import sys

from .bots import FirstBot
from .engine import Round
from .selfplay import play_runde, random_deal
from .svaer import Svaer

LEVELS = {"first": FirstBot, "svaer": Svaer}


def seat_points(deal, dealer, seat, level, field, seed):
    bots = [LEVELS[field](seed * 4 + s) for s in range(4)]
    bots[seat] = LEVELS[level](seed * 4 + seat)
    r = play_runde(Round(deal, dealer), bots, check=False)
    return float(r.points()[seat]) if r.complete() else 0.0


def duplicate(deals, seed, field="first"):
    rng = random.Random(seed)
    diffs = []
    svaer_total = first_total = 0.0
    for index in range(deals):
        deal = random_deal(rng)
        dealer = index % 4
        game_seed = rng.randrange(1 << 30)
        for seat in range(4):
            a = seat_points(deal, dealer, seat, "svaer", field, game_seed)
            b = seat_points(deal, dealer, seat, "first", field, game_seed)
            svaer_total += a
            first_total += b
            diffs.append(a - b)
    n = len(diffs)
    mean = sum(diffs) / n
    sd = math.sqrt(sum((d - mean) ** 2 for d in diffs) / (n - 1))
    return {"n": n, "delta": mean, "ci95": 1.96 * sd / math.sqrt(n),
            "svaer": svaer_total / n, "first": first_total / n}


def main(argv):
    deals = int(argv[1]) if len(argv) > 1 else 2000
    seed = int(argv[2]) if len(argv) > 2 else 1
    fields = [argv[3]] if len(argv) > 3 else ["first", "svaer"]
    for field in fields:
        r = duplicate(deals, seed, field)
        print(f"field {field:5}: {r['n']} hands  Svær {r['svaer']:+.3f}  first bot {r['first']:+.3f}  "
              f"Δ Svær − first {r['delta']:+.3f} ± {r['ci95']:.3f} points per runde (95 %)")


if __name__ == "__main__":
    main(sys.argv)
