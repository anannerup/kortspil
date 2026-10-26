"""A rating on a fixed scale: how much better a net (or a bot) is.

The scale is Elo-style, like tools/botlab's `eval`: the measured player
sits in one seat against a field of three FirstBots and plays whole spil
of SPIL_RUNDER runder (a redeal does not count). Its win share p (the
share of spil it ends highest; ties split) is turned into the rating
difference d to each of three equal opponents at which a four-way
Bradley–Terry model gives p:

    p = s / (s + 3),  s = 10^(d / 400),  so  d = 400 · log10(3p / (1 − p)).

So the field's own level, FirstBot, is 0 (p = 25 %), and Svær sits at
SVAER_RATING (measured once with `train rating --svaer`).

Same-hand duplicate, so the cards do not decide it: each spil is played
twice from the same seed (the same deals in the same order, the same seeds
for the field's bots), once with the measured player in the seat and once
with FirstBot there. The win share used is p = 25 % + the paired
difference (measured − FirstBot in the same seat, same spil), which
cancels most of the card luck; its 95 % interval is that of the paired
difference, carried through the formula. The measured seat goes round
(spil i: seat i % 4). The net sees each runde's place in the spil and the
standing (spil.SpilContext), as in training.
"""

import math
import random

from .agent import NetPlayer, play
from .bots import FirstBot
from .engine import Round
from .rules import STANDARD
from .selfplay import random_deal
from .spil import SPIL_RUNDER, SpilContext, win_share

MAX_DEALS = 200


def elo(p):
    """The rating d from a win share p against three equal opponents."""
    p = min(max(p, 1e-6), 1 - 1e-6)
    return 400 * math.log10(3 * p / (1 - p))


def share_of(rating):
    """The win share against three FirstBots at a rating (the inverse)."""
    s = 10 ** (rating / 400)
    return s / (s + 3)


def play_spil(players, seed):
    """One spil of SPIL_RUNDER runder from `seed`: (totals, runder, stats).
    stats counts, for each seat, melder runder and those that went home."""
    rng = random.Random(seed)
    dealer = rng.randrange(4)
    totals = [0.0] * 4
    played = deals = 0
    melder = [[0, 0] for _ in range(4)]
    exchanged = {}
    while played < SPIL_RUNDER and deals < MAX_DEALS:
        r = Round(random_deal(rng), dealer, STANDARD)
        play(r, players, stats=exchanged, spil=SpilContext(played, SPIL_RUNDER, tuple(totals)))
        deals += 1
        if r.complete():
            played += 1
            for seat, points in enumerate(r.points()):
                totals[seat] += float(points)
            result = r.result()
            melder[result["melder"]][0] += 1
            melder[result["melder"]][1] += bool(result["gik_hjem"])
        dealer = r.next_dealer()
    return totals, played, melder, exchanged


def _make(spec, seed):
    kind = spec[0]
    if kind == "first":
        return FirstBot(seed)
    if kind == "svaer":
        from .svaer import Svaer
        return Svaer()
    return NetPlayer(spec[1])  # ("net", model)


def _spil_pair(spec, index, seed):
    rng = random.Random(seed * 1_000_003 + index)
    spil_seed = rng.randrange(1 << 62)
    field_seeds = [rng.randrange(1 << 30) for _ in range(4)]
    seat = index % 4
    out = []
    for measured in (spec, ("first",)):
        players = [FirstBot(field_seeds[s]) for s in range(4)]
        players[seat] = _make(measured, field_seeds[seat])
        totals, runder, melder, exchanged = play_spil(players, spil_seed)
        out.append((win_share(totals, seat), totals[seat] / max(runder, 1), melder[seat], exchanged))
    return out


def _chunk(args):
    spec, state_dict, config_dict, start, stop, seed = args
    import torch
    torch.set_num_threads(1)
    if spec[0] == "net":
        from .config import Config
        from .net import build
        model = build(Config.from_dict(config_dict))
        model.load_state_dict(state_dict)
        model.eval()
        spec = ("net", model)
    return [_spil_pair(spec, index, seed) for index in range(start, stop)]


def _mean_ci(values):
    n = len(values)
    mean = sum(values) / n
    var = sum((v - mean) ** 2 for v in values) / (n - 1) if n > 1 else 0.0
    return mean, 1.96 * math.sqrt(var / n)


def rate(player="net", model=None, config=None, spil=400, seed=11, workers=1):
    """The rating of the net (`model`) or of a bot ("svaer", "first") over
    `spil` duplicate spil: rating with its 95 % interval, the win shares,
    Δ points per runde against FirstBot in the same seat, melder share and
    home share, and (for the net) how often it exchanged 0-3 cards."""
    spec = ("net",) if player == "net" else (player,)
    state = None
    if player == "net":
        state = {k: v.detach().cpu() for k, v in model.state_dict().items()}
    bounds = [(spil * i // workers, spil * (i + 1) // workers) for i in range(workers)]
    jobs = [(spec, state, config.to_dict() if config else None, a, b, seed) for a, b in bounds if b > a]
    if workers > 1:
        import torch.multiprocessing as mp
        with mp.get_context("spawn").Pool(workers) as pool:
            parts = pool.map(_chunk, jobs)
    else:
        parts = [_chunk(job) for job in jobs]
    pairs = [p for part in parts for p in part]
    diff, ci = _mean_ci([m[0] - b[0] for m, b in pairs])
    p = 0.25 + diff
    points, points_ci = _mean_ci([m[1] - b[1] for m, b in pairs])
    melder = [sum(m[2][0] for m, _ in pairs), sum(m[2][1] for m, _ in pairs)]
    runder = SPIL_RUNDER * len(pairs)
    exchanged = {}
    for m, _ in pairs:
        for key, counts in m[3].items():
            total = exchanged.setdefault(key, [0, 0, 0, 0])
            for n, c in enumerate(counts):
                total[n] += c
    return {
        "player": player, "spil": len(pairs), "seed": seed,
        "rating": elo(p), "rating_ci": [elo(p - ci), elo(p + ci)],
        "win": p, "win_ci": ci, "win_raw": sum(m[0] for m, _ in pairs) / len(pairs),
        "first_win_raw": sum(b[0] for _, b in pairs) / len(pairs),
        "vs_first": {"mean": points, "ci95": points_ci},
        "melder": {"share": melder[0] / runder, "home": melder[1] / melder[0] if melder[0] else 0.0},
        "exchanged": exchanged,
    }


# Svær on the scale: `python -m esmakker_ai.train rating --svaer --spil 20000 --workers 18`
# (seed 11, makker 3½ stik): +462 [+453, +471], win share 82.6 % ± 0.8 %, +3.48 ± 0.04 point/runde
# over FirstBot (with makker 2 stik it was +464). Re-measure when Svær or the rules change.
SVAER_RATING = 462
