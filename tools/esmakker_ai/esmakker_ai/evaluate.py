"""Same-hand duplicate play against FirstBot (like tools/botlab `hands`).

Every deal is played once per measured seat with the net in that seat and
once with FirstBot there: the same cards, the same kortgiver, the same
field (FirstBot on the three other seats with the same seeds). Only the
measured seat's player changes, so the difference on a deal is its own
doing. A redeal counts as a runde with 0 points. Reported: points per runde
for the net and for FirstBot in the seat, and the paired difference, each
with a 95 % confidence interval; plus the share of deals the net did
better, the same and worse.

Each deal is a lone runde: the net sees it as the first runde of a spil
at 0-0-0-0 (features.encode with no spil context), so this measures the
opening runde's play; the rating (rating.py) plays whole spil.

`reference="svaer"` puts Svær (strategy §6) in the measured seat;
`field="svaer"` makes the three others Svær (the human-like table).
`reference="pass"` puts PassBot in the measured seat instead of FirstBot
(the field stays FirstBot): FirstBot that never melder. Most of what a
young net gains on FirstBot is not melding 9 on every hand; beating
PassBot shows it learned more than that.
"""

import math
import random

from . import actions as A
from .agent import NetPlayer, play
from .bots import FirstBot
from .svaer import Svaer
from .engine import Round
from .rules import STANDARD
from .selfplay import random_deal


def _stats(values):
    n = len(values)
    mean = sum(values) / n
    var = sum((v - mean) ** 2 for v in values) / (n - 1) if n > 1 else 0.0
    return {"mean": mean, "ci95": 1.96 * math.sqrt(var / n), "n": n}


class PassBot(FirstBot):
    """FirstBot that always passes in the meldingsrunde."""

    def act(self, obs):
        return A.PAS if obs["phase"] == "bidding" else super().act(obs)


REFERENCES = {"first": FirstBot, "pass": PassBot, "svaer": Svaer}
NAMES = {"first": "FirstBot", "pass": "PassBot", "svaer": "Svær"}


def _deal_points(model, index, seed, rules, reference="first", field="first", stats=None):
    rng = random.Random(seed * 1_000_003 + index)
    deal = random_deal(rng)
    dealer = index % 4
    field_seeds = [rng.randrange(1 << 30) for _ in range(4)]
    out = []
    for seat in range(4):
        scores = []
        melder = []
        for measured in ("net", "first"):
            players = [REFERENCES[field](field_seeds[s]) for s in range(4)]
            if measured == "net":
                players[seat] = NetPlayer(model)
            else:
                players[seat] = REFERENCES[reference](field_seeds[seat])
            r = Round(deal, dealer, rules)
            play(r, players, stats=stats if measured == "net" else None)
            scores.append(float(r.points()[seat]) if r.complete() else 0.0)
            result = r.result()
            melder.append(result["gik_hjem"] if result and result["melder"] == seat else None)
        out.append((*scores, *melder))
    return out


def _chunk(args):
    state_dict, config_dict, start, stop, seed, rules, reference, field = args
    import torch
    from .config import Config
    from .net import build
    torch.set_num_threads(1)
    model = build(Config.from_dict(config_dict))
    model.load_state_dict(state_dict)
    model.eval()
    out = []
    stats = {}
    for index in range(start, stop):
        out.extend(_deal_points(model, index, seed, rules, reference, field, stats))
    return out, stats


def duplicate(model, deals=1000, seed=1, rules=STANDARD, workers=1, config=None, reference="first", field="first"):
    """The duplicate report: {"net", "first", "diff"} as mean/ci95/n, and
    "better"/"same"/"worse" shares."""
    if workers > 1:
        import torch.multiprocessing as mp
        if config is None:
            raise ValueError("workers > 1 needs the model's config")
        state = {k: v.cpu() for k, v in model.state_dict().items()}
        bounds = [(deals * i // workers, deals * (i + 1) // workers) for i in range(workers)]
        with mp.get_context("spawn").Pool(workers) as pool:
            parts = pool.map(_chunk, [(state, config.to_dict(), a, b, seed, rules, reference, field) for a, b in bounds])
        pairs = [p for part, _ in parts for p in part]
        exchanged = {}
        for _, stats in parts:
            for key, counts in stats.items():
                total = exchanged.setdefault(key, [0, 0, 0, 0])
                for n, c in enumerate(counts):
                    total[n] += c
    else:
        pairs = []
        exchanged = {}
        for index in range(deals):
            pairs.extend(_deal_points(model, index, seed, rules, reference, field, exchanged))
    net = [p[0] for p in pairs]
    first = [p[1] for p in pairs]
    diff = [a - b for a, b in zip(net, first)]
    n = len(pairs)

    def melder(column):
        runder = [p[column] for p in pairs if p[column] is not None]
        return {"share": len(runder) / n, "home": sum(runder) / len(runder) if runder else 0.0}

    return {"net": _stats(net), "first": _stats(first), "diff": _stats(diff),
            "better": sum(d > 0 for d in diff) / n, "same": sum(d == 0 for d in diff) / n,
            "worse": sum(d < 0 for d in diff) / n, "net_melder": melder(2), "first_melder": melder(3),
            "deals": deals, "seed": seed, "reference": reference, "field": field, "exchanged": exchanged}


def format_report(report):
    ref = NAMES[report.get("reference", "first")]
    field = NAMES[report.get("field", "first")]

    def line(name, s):
        return f"  {name:16} {s['mean']:+8.3f} ± {s['ci95']:.3f}"
    return "\n".join([
        f"same-hand duplicate, {ref} in the seat vs the net, {field} field: {report['deals']} deals × 4 seats = {report['net']['n']} runder, "
        f"seed {report['seed']}",
        "points per runde (95 % CI):",
        line("net", report["net"]),
        line(ref, report["first"]),
        line(f"net − {ref}", report["diff"]),
        f"  same hand: net better {report['better']:.1%}, same {report['same']:.1%}, worse {report['worse']:.1%}",
        f"  melder: net {report['net_melder']['share']:.1%} of runder (home {report['net_melder']['home']:.1%}), "
        f"{ref} {report['first_melder']['share']:.1%} (home {report['first_melder']['home']:.1%})",
        *([f"  net exchanged {format_exchanged(report['exchanged'])}"] if report.get("exchanged") else []),
    ])


def format_exchanged(exchanged):
    """"stik 0/1/2/3: 4/0/3/80 (5/0/3/92 %); sol ..." from {"exchanged": [..], "sol_exchanged": [..]}."""
    parts = []
    for key, name in (("exchanged", "stik"), ("sol_exchanged", "sol")):
        counts = exchanged.get(key)
        if counts and sum(counts):
            share = "/".join(f"{100 * c / sum(counts):.0f}" for c in counts)
            parts.append(f"{name} 0/1/2/3 cards: {'/'.join(map(str, counts))} ({share} %)")
    return "; ".join(parts) or "never"
