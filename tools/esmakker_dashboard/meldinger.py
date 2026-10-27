"""What the net melder at each snapshot, for the dashboard.

For every snapshot in a run that has no count yet, plays the same deals at
two tables and counts the final melding and whether the melder went home, and in
self-play the net's own stik guesses for the melder and makker at the
melder's first bid against what they took (with a contract head also its
contract guess: the side's expected stik with the trump the melder chose):

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


def count(model, deals, seed, self_deals=None):
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
    # (the side's expected stik with the chosen trump, the side's stik, the trump, the guessed chance of
    # those stik), contract nets only
    contracts = []

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
                if "contract_stik" in e:
                    side = result["stik"]
                    contracts.append((e["contract_stik"][r.trump], side, r.trump, e["contract_dist"][r.trump][side]))
                return
            probe.apply(seat, action, check=False)

    net = NetPlayer(model)
    for index in range(max(deals, self_deals or deals)):
        rng = random.Random(seed * 1_000_003 + index)
        deal = random_deal(rng)
        dealer = index % 4
        seeds = [rng.randrange(1 << 30) for _ in range(4)]
        if index < deals:
            for seat in range(4):
                players = [Svaer(seeds[s]) for s in range(4)]
                players[seat] = net
                r = Round(deal, dealer, STANDARD)
                play(r, players)
                tally("svaer", r, {seat})
        if index >= (self_deals or deals):
            continue
        r = Round(deal, dealer, STANDARD)
        play(r, [net] * 4)
        tally("self", r, {0, 1, 2, 3})
        guess(r)
    out = {name: {"runder": t["runder"], "melding": dict(t["melding"]), "home": dict(t["home"])}
           for name, t in tables.items()}
    out["guess"] = summary(guesses, contracts)
    return out


def summary(guesses, contracts=()):
    """Mean guess, mean actual and mean absolute error for own, makker and
    the two together, over the self-play stik runder; with `contracts` also
    the contract guess against the side's stik."""
    if not guesses:
        return {"n": 0}

    def part(g, a):
        return {"guess": round(sum(g) / len(g), 2), "actual": round(sum(a) / len(a), 2),
                "error": round(sum(abs(x - y) for x, y in zip(g, a)) / len(g), 2)}

    own_g, mate_g, own_a, mate_a = zip(*guesses)
    out = {"n": len(guesses), "own": part(own_g, own_a), "makker": part(mate_g, mate_a),
           "together": part([o + m for o, m in zip(own_g, mate_g)], [o + m for o, m in zip(own_a, mate_a)])}
    if contracts:
        out["contract"] = {**part([c[0] for c in contracts], [c[1] for c in contracts]), **learnt(contracts)}
    return out


def learnt(contracts):
    """Whether the contract head reads the hand: its cross-entropy at the
    side's stik with the chosen trump against a guess blind to the hand
    (each trump's frequencies of the side's stik over the same runder: a
    bar the head must get under), and the correlation of its expected stik
    with the side's."""
    import math
    freq = {}
    for _, side, trump, _ in contracts:
        freq.setdefault(trump, Counter())[side] += 1
    n = len(contracts)
    ce = -sum(math.log(max(p, 1e-9)) for *_, p in contracts) / n
    blind = -sum(math.log(freq[t][s] / sum(freq[t].values())) for _, s, t, _ in contracts) / n
    out = {"ce": round(ce, 3), "blind_ce": round(blind, 3)}
    guess = [c[0] for c in contracts]
    actual = [c[1] for c in contracts]
    mg, ma = sum(guess) / n, sum(actual) / n
    cov = sum((g - mg) * (a - ma) for g, a in zip(guess, actual))
    sg = math.sqrt(sum((g - mg) ** 2 for g in guess))
    sa = math.sqrt(sum((a - ma) ** 2 for a in actual))
    if sg and sa:
        out["corr"] = round(cov / (sg * sa), 3)
    return out


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--run", default="main")
    p.add_argument("--runs-dir", default=str(DEFAULT_RUNS))
    # mostly self-play, as in training (Anders): 100 deals x 4 seats at the
    # Svær table, 2 000 runder in self-play, five times as many
    p.add_argument("--deals", type=int, default=100)
    p.add_argument("--self-deals", type=int, default=2000)
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
    # counts from before the stik guess or the self-play share are made again
    stale = [name for name, e in entries.items() if "guess" not in e or e.get("self_deals") != args.self_deals
             or ("contract" in e["guess"] and "ce" not in e["guess"]["contract"])]
    if stale:
        for name in stale:
            del entries[name]
        out.write_text("".join(json.dumps(e) + "\n" for e in entries.values()), encoding="utf-8")
    done = set(entries)
    for path in sorted((run / "snapshots").glob("step_*.pt")):
        if path.name in done:
            continue
        model, saved = load_weights(path)
        entry = {"file": path.name, "step": saved["counters"]["steps"], "deals": args.deals,
                 "self_deals": args.self_deals, "seed": args.seed,
                 **count(model, args.deals, args.seed, args.self_deals)}
        with out.open("a", encoding="utf-8") as f:
            f.write(json.dumps(entry) + "\n")
        print(f"{path.name}: {entry['svaer']['melding']}", flush=True)


if __name__ == "__main__":
    main()
