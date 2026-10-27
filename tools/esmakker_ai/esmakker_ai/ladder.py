"""The ladder: is the net better than its own earlier versions? (Anders: "det
den kæmpede med for lidt siden skal den nemt slå".)

Each new snapshot plays same-hand duplicate against older snapshots of the
run. A deal is played in one seat (deal i: seat i % 4, kortgiver i % 4) four
times: the new net in the seat with the old net on the three others, and
the old net in the seat with the same old field; then the same two with the
new net as the field. The paired difference (new in the seat - old in the
seat, same cards, same field) is the new net's doing; the two fields are
averaged, so neither the old nor the new table decides it. Each deal is a
lone runde (the first of a spil at 0-0-0-0), as evaluate.py.

The gate (config ladder_gap): against the snapshot ladder_gap snapshots
earlier (3 = 60 000 steps) on ladder_deals deals (x 2 fields: 2 000 paired
runder at 1 000), point/runde with its 95 % interval; "gate" is True when
the interval lies above 0. The other earlier snapshots (at most
ladder_all_most, spread evenly) get ladder_deals_all deals each. One line
per (snapshot, older, mode) in <run>/ladder.jsonl.

`mode`: how the bot melder. "net": the net alone (NetPlayer). "sim": the
bot that melder by simulation (agent.SimulatingPlayer, part of the
simulation work), when that exists.
"""

import json
import math
import random
import time
from pathlib import Path

LADDER = "ladder.jsonl"
SEED = 21  # the same deals for every comparison, so the ladder's rows are comparable


def _stats(values):
    n = len(values)
    mean = sum(values) / n if n else 0.0
    var = sum((v - mean) ** 2 for v in values) / (n - 1) if n > 1 else 0.0
    return {"mean": mean, "ci95": 1.96 * math.sqrt(var / n) if n else 0.0, "n": n}


def modes():
    """The bidding modes there are: always "net", "sim" once the bot that
    melder by simulation exists."""
    from . import agent
    return ["net", "sim"] if getattr(agent, "SimulatingPlayer", None) is not None else ["net"]


def player(model, mode):
    from . import agent
    if mode == "sim":
        return agent.SimulatingPlayer(model)
    return agent.NetPlayer(model)


def deal_diffs(new, old, index, seed, mode="net", rules=None):
    """(new - old in the seat with the old field, new - old in the seat
    with the new field) on deal `index`, in points (redeal: 0)."""
    from .agent import play
    from .engine import Round
    from .rules import STANDARD
    from .selfplay import random_deal
    rules = rules or STANDARD
    rng = random.Random(seed * 1_000_003 + index)
    deal = random_deal(rng)
    dealer = seat = index % 4
    a, b = player(new, mode), player(old, mode)

    def points(field, measured):
        players = [field] * 4
        players[seat] = measured
        r = Round(deal, dealer, rules)
        play(r, players)
        return float(r.points()[seat]) if r.complete() else 0.0
    return points(b, a) - points(b, b), points(a, a) - points(a, b)


def _chunk(args):
    new_path, old_path, start, stop, seed, mode = args
    import torch
    torch.set_num_threads(1)
    from .learner import load_weights
    new, _ = load_weights(new_path)
    old, _ = load_weights(old_path)
    return [deal_diffs(new, old, i, seed, mode) for i in range(start, stop)]


def compare(new_path, old_path, deals, seed=SEED, mode="net", workers=1):
    """The duplicate report of `new_path` against `old_path`: "diff" (both
    fields averaged per deal), "old_field" and "new_field", as mean/ci95/n
    in point/runde; "better"/"worse" shares of deals."""
    bounds = [(deals * i // workers, deals * (i + 1) // workers) for i in range(workers)]
    jobs = [(str(new_path), str(old_path), a, b, seed, mode) for a, b in bounds if b > a]
    if workers > 1:
        import torch.multiprocessing as mp
        with mp.get_context("spawn").Pool(len(jobs)) as pool:
            parts = pool.map(_chunk, jobs)
    else:
        parts = [_chunk(job) for job in jobs]
    pairs = [p for part in parts for p in part]
    diff = [(x + y) / 2 for x, y in pairs]
    return {"diff": _stats(diff), "old_field": _stats([x for x, _ in pairs]),
            "new_field": _stats([y for _, y in pairs]),
            "better": sum(d > 0 for d in diff) / len(diff), "worse": sum(d < 0 for d in diff) / len(diff),
            "runder": 2 * len(pairs)}


def plan(files, gap, most):
    """[(new, older, kind)] for the snapshots `files` (sorted by step): each
    against the one `gap` before it ("gate"; the first one when fewer came
    before) and against at most `most` other earlier ones spread evenly ("all")."""
    out = []
    for i in range(1, len(files)):
        gate = files[max(0, i - gap)]
        out.append((files[i], gate, "gate"))
        others = [f for f in files[:i] if f != gate]
        if len(others) > most:
            step = len(others) / most
            others = [others[int(k * step)] for k in range(most)]
        out.extend((files[i], f, "all") for f in others)
    return out


def read(run_dir):
    path = Path(run_dir) / LADDER
    if not path.exists():
        return []
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


def _step(path):
    return int(Path(path).stem.split("_")[1])


def run_pending(run_dir, config, workers=None, echo=print):
    """Plays every comparison of the plan not in ladder.jsonl yet (the
    gates first, newest snapshot first), appending each as it is done."""
    from .learner import SNAPSHOTS
    if not config.ladder_deals:
        return []
    run_dir = Path(run_dir)
    files = sorted((run_dir / SNAPSHOTS).glob("step_*.pt"))
    done = {(e["file"], e["vs"], e["mode"]) for e in read(run_dir)}
    todo = [(n, o, k, m) for n, o, k in plan(files, config.ladder_gap, config.ladder_all_most) for m in modes()
            if (n.name, o.name, m) not in done]
    todo.sort(key=lambda t: (t[2] != "gate", -_step(t[0]), t[3] != "net"))
    workers = workers or max(1, int(config.ladder_workers))
    written = []
    for new, old, kind, mode in todo:
        deals = config.ladder_deals if kind == "gate" else config.ladder_deals_all
        started = time.time()
        report = compare(new, old, deals, mode=mode, workers=workers)
        d = report["diff"]
        entry = {"file": new.name, "step": _step(new), "vs": old.name, "vs_step": _step(old), "kind": kind,
                 "mode": mode, "deals": deals, "seed": SEED, **report,
                 "significant": d["mean"] - d["ci95"] > 0, "worse_significant": d["mean"] + d["ci95"] < 0,
                 "seconds": round(time.time() - started, 1)}
        with (run_dir / LADDER).open("a") as f:
            f.write(json.dumps(entry) + "\n")
        written.append(entry)
        echo(f"ladder {new.name} vs {old.name} ({kind}, {mode}): {d['mean']:+.3f} ± {d['ci95']:.3f} point/runde")
    return written
