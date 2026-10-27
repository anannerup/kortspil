"""What the net melder at each snapshot, for the dashboard.

For every snapshot in a run that has no count yet, plays the same deals at
two tables and counts the final melding and whether the melder went home, and in
self-play the net's own stik guesses for the melder and makker at the
melder's first bid against what they took:

- "svaer": the net in one seat, three Svær (each deal once per seat), the
  same table as the rating's "mod Svær"
- "self": the net in all four seats, as in training

Appends one line per snapshot to <run>/meldinger.jsonl. Reads the run's
snapshots only; never touches the training. Needs the esmakker_ai venv:

    cd tools\\esmakker_ai
    .venv\\Scripts\\python.exe ..\\esmakker_dashboard\\meldinger.py --run searchbot
"""

import argparse
import json
import os
import random
import sys
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
AI = HERE.parent / "esmakker_ai"
sys.path.insert(0, str(AI))

DEFAULT_RUNS = Path(os.environ.get("ESMAKKER_RUNS") or AI / "runs")


def count(model, deals, seed):
    import torch
    from esmakker_ai.agent import NetPlayer, explain, play
    from esmakker_ai.engine import Round
    from esmakker_ai.rules import STANDARD
    from esmakker_ai.selfplay import random_deal
    from esmakker_ai.svaer import Svaer

    torch.set_num_threads(2)
    tables = {"svaer": {"melding": Counter(), "home": Counter(), "runder": 0},
              "self": {"melding": Counter(), "home": Counter(), "runder": 0}}

    def tally(table, r, seats):
        t = tables[table]
        t["runder"] += 1
        result = r.result()
        if not result or result["melder"] is None or result["melder"] not in seats:
            t["melding"]["pas"] += 1
            return
        t["melding"][result["melding"]] += 1
        t["home"][result["melding"]] += int(bool(result["gik_hjem"]))

    guesses = []  # (own guess, makker guess, own actual, makker actual) at the melder's first bid

    def guess(r):
        """The net's own stik guesses for the melder and makker at the
        melder's first bid decision, against what they took."""
        result = r.result()
        if not result or result["kind"] != "played":
            return
        melder, mate = result["melder"], result["esmakker"]
        probe = Round(r.deal, r.dealer, r.rules)
        for seat, action in r.log:
            if probe.phase != "bidding":
                return
            if seat == melder:
                e = explain(model, probe, seat)
                taken = r.tricks_won[mate] if mate is not None and mate != melder else 0
                guesses.append((e["own_stik"], e["makker_stik"], r.tricks_won[melder], taken))
                return
            probe.apply(seat, action, check=False)

    net = NetPlayer(model)
    for index in range(deals):
        rng = random.Random(seed * 1_000_003 + index)
        deal = random_deal(rng)
        dealer = index % 4
        seeds = [rng.randrange(1 << 30) for _ in range(4)]
        for seat in range(4):
            players = [Svaer(seeds[s]) for s in range(4)]
            players[seat] = net
            r = Round(deal, dealer, STANDARD)
            play(r, players)
            tally("svaer", r, {seat})
        r = Round(deal, dealer, STANDARD)
        play(r, [net] * 4)
        tally("self", r, {0, 1, 2, 3})
        guess(r)
    out = {name: {"runder": t["runder"], "melding": dict(t["melding"]), "home": dict(t["home"])}
           for name, t in tables.items()}
    out["guess"] = summary(guesses)
    return out


def summary(guesses):
    """Mean guess, mean actual and mean absolute error for own, makker and
    the two together, over the self-play stik runder."""
    if not guesses:
        return {"n": 0}

    def part(g, a):
        return {"guess": round(sum(g) / len(g), 2), "actual": round(sum(a) / len(a), 2),
                "error": round(sum(abs(x - y) for x, y in zip(g, a)) / len(g), 2)}

    own_g, mate_g, own_a, mate_a = zip(*guesses)
    return {"n": len(guesses), "own": part(own_g, own_a), "makker": part(mate_g, mate_a),
            "together": part([o + m for o, m in zip(own_g, mate_g)], [o + m for o, m in zip(own_a, mate_a)])}


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--run", default="main")
    p.add_argument("--runs-dir", default=str(DEFAULT_RUNS))
    p.add_argument("--deals", type=int, default=200)
    p.add_argument("--seed", type=int, default=11)
    args = p.parse_args()

    from esmakker_ai.learner import load_weights

    run = Path(args.runs_dir) / args.run
    out = run / "meldinger.jsonl"
    entries = {}
    if out.exists():
        for line in out.read_text(encoding="utf-8").splitlines():
            if line.strip():
                e = json.loads(line)
                entries[e["file"]] = e
    # counts from before the stik guess was added are made again
    stale = [name for name, e in entries.items() if "guess" not in e]
    if stale:
        for name in stale:
            del entries[name]
        out.write_text("".join(json.dumps(e) + "\n" for e in entries.values()), encoding="utf-8")
    done = set(entries)
    for path in sorted((run / "snapshots").glob("step_*.pt")):
        if path.name in done:
            continue
        model, saved = load_weights(path)
        entry = {"file": path.name, "step": saved["counters"]["steps"], "deals": args.deals, "seed": args.seed,
                 **count(model, args.deals, args.seed)}
        with out.open("a", encoding="utf-8") as f:
            f.write(json.dumps(entry) + "\n")
        print(f"{path.name}: {entry['svaer']['melding']}", flush=True)


if __name__ == "__main__":
    main()
