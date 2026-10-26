"""Training commands (run from tools/esmakker_ai):

    python -m esmakker_ai.train start  [--run NAME] [--config FILE] [--set key=value ...]
    python -m esmakker_ai.train stop   [--run NAME]
    python -m esmakker_ai.train status [--run NAME]
    python -m esmakker_ai.train eval   [--run NAME | --weights FILE] [--deals N] [--seed S] [--workers W] [--reference first|pass|svaer] [--field first|svaer]
    python -m esmakker_ai.train snapshots [--run NAME]
    python -m esmakker_ai.train rating [--run NAME] [--snapshot FILE | --all | --svaer] [--spil N] [--deals N] [--workers W] [--csv]

A run lives in <runs dir>/<NAME> (default tools/esmakker_ai/runs/main,
gitignored; --runs-dir or ESMAKKER_RUNS moves it). `start` resumes when the
run has a checkpoint; Ctrl+C or `stop` saves and ends it.
"""

import argparse
import json
import sys
import time
from pathlib import Path

from . import config as cfg


def run_dir(args):
    return cfg.runs_root(args.runs_dir) / args.run


def cmd_start(args):
    from .learner import CHECKPOINT, Run, train
    from .partners import factory
    directory = run_dir(args)
    try:
        cfg.check_run(directory)
    except cfg.IncompatibleRun as e:
        print(e)
        return 1
    run = Run(directory)
    if run.running():
        print(f"{directory} is already running (pid {run.status()['pid']}); stop it first")
        return 1
    saved = directory / "config.json"
    if saved.exists():
        config = cfg.load(saved)
        if args.config:
            print("note: the run has its settings already; --config is ignored (use --set to change one)")
    else:
        config = cfg.load(args.config) if args.config else cfg.Config()
    config.override(args.set)
    factory(config.partner)
    directory.mkdir(parents=True, exist_ok=True)
    cfg.save(config, saved)
    if not (directory / CHECKPOINT).exists():
        print(f"settings: {json.dumps(config.to_dict())}")
    train(config, directory, max_steps=args.max_steps, max_seconds=args.max_minutes * 60 if args.max_minutes else None,
          init=args.init)
    return 0


def cmd_stop(args):
    from .learner import STOP, Run
    directory = run_dir(args)
    run = Run(directory)
    if not run.running():
        print(f"{directory} is not running")
        return 0
    (directory / STOP).write_text("stop\n")
    print("asked to stop; waiting for the checkpoint ...")
    deadline = time.time() + args.wait
    while time.time() < deadline:
        status = run.status()
        if status and status.get("state") == "stopped":
            print(f"stopped at step {status['counters']['steps']}")
            return 0
        time.sleep(1)
    print("still saving or not answering; check `status` again shortly")
    return 1


def cmd_status(args):
    from .learner import Run
    directory = run_dir(args)
    run = Run(directory)
    status = run.status()
    if status is None:
        print(f"{directory}: no run here")
        return 1
    state = "running" if run.running() else ("stopped" if status["state"] == "stopped" else "not answering (crashed?)")
    c = status["counters"]
    print(f"{directory}: {state}, updated {status['updated']}, device {status['device']}, {status['actors']} actors")
    print(f"  steps {c['steps']}  runder {c['runder']}  samples {c['samples']}  replay {status['replay']}  "
          f"resumes {c['resumes']}")
    if status.get("rates"):
        r = status["rates"]
        print(f"  {r.get('runder_per_s')} runder/s  {r.get('samples_per_s')} samples/s  {r.get('steps_per_s')} steps/s")
    if status.get("losses"):
        print("  losses " + "  ".join(f"{k} {v:.4f}" for k, v in status["losses"].items()))
    for snap in status.get("snapshots") or []:
        print(f"  snapshot {snap['file']}" + (f"  vs FirstBot {snap['eval']['diff']['mean']:+.2f}" if "eval" in snap else ""))
    ratings = read_ratings(directory)
    if ratings:
        print("  latest rating: " + rating_line(ratings[-1]))
    return 0


# -- rating ----------------------------------------------------------------------

RATINGS = "ratings.jsonl"


def read_ratings(directory):
    """The run's ratings, one per file (the latest rating of it), by step."""
    path = Path(directory) / RATINGS
    if not path.exists():
        return []
    latest = {}
    for line in path.read_text().splitlines():
        if line.strip():
            e = json.loads(line)
            latest[e["file"]] = e
    return sorted(latest.values(), key=lambda e: (e["step"], e["file"] != "checkpoint.pt"))


def hours(seconds):
    return f"{(seconds or 0) / 3600:.2f} h"


def rating_line(e):
    lo, hi = e["rating_ci"]
    return (f"step {e['step']} ({hours(e.get('seconds'))}): rating {e['rating']:+.0f} [{lo:+.0f}, {hi:+.0f}]  "
            f"vs Svær {e['vs_svaer']['mean']:+.2f} ± {e['vs_svaer']['ci95']:.2f}  "
            f"vs PassBot {e['vs_pass']['mean']:+.2f} ± {e['vs_pass']['ci95']:.2f} point/runde")


def rating_table(ratings):
    from .rating import SVAER_RATING
    lines = [f"rating: 0 = FirstBot, Svær = {SVAER_RATING:+.0f}" if SVAER_RATING is not None else "rating: 0 = FirstBot",
             f"{'file':24} {'step':>9} {'trained':>8} {'rating':>7} {'95 % CI':>13} {'vs Svær':>14} {'vs PassBot':>14} "
             f"{'melder':>7} {'home':>5} {'Svær t. melder/home':>19}"]
    for e in ratings:
        lo, hi = e["rating_ci"]
        sv, ps = e["vs_svaer"], e["vs_pass"]
        lines.append(f"{e['file']:24} {e['step']:>9} {hours(e.get('seconds')):>8} {e['rating']:>+7.0f} "
                     f"[{lo:+5.0f},{hi:+5.0f}] {sv['mean']:>+7.2f} ± {sv['ci95']:.2f} {ps['mean']:>+7.2f} ± {ps['ci95']:.2f} "
                     f"{e['melder']['share']:>7.1%} {e['melder']['home']:>5.0%} "
                     f"{e['svaer_table_melder']['share']:>9.1%} / {e['svaer_table_melder']['home']:.0%}")
    return "\n".join(lines)


def write_csv(directory, ratings):
    import csv
    path = Path(directory) / "ratings.csv"
    with path.open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["file", "step", "hours_trained", "runder", "rating", "rating_lo", "rating_hi", "vs_svaer",
                    "vs_svaer_ci95", "vs_pass", "vs_pass_ci95", "melder_share", "melder_home", "spil", "deals"])
        for e in ratings:
            w.writerow([e["file"], e["step"], round((e.get("seconds") or 0) / 3600, 3), e.get("runder"),
                        round(e["rating"], 1), round(e["rating_ci"][0], 1), round(e["rating_ci"][1], 1),
                        round(e["vs_svaer"]["mean"], 4), round(e["vs_svaer"]["ci95"], 4), round(e["vs_pass"]["mean"], 4),
                        round(e["vs_pass"]["ci95"], 4), round(e["melder"]["share"], 4), round(e["melder"]["home"], 4),
                        e["spil"], e["deals"]])
    return path


def rate_weights(path, spil, deals, workers, seed):
    """One ratings.jsonl entry for a snapshot or checkpoint file."""
    from .evaluate import duplicate
    from .learner import load_weights
    from .rating import rate
    model, saved = load_weights(path)
    config = cfg.Config.from_dict(saved["config"])
    counters = saved["counters"]
    started = time.time()
    rated = rate("net", model, config, spil=spil, seed=seed, workers=workers)
    svaer = duplicate(model, deals=deals, seed=seed, workers=workers, config=config, reference="svaer", field="svaer")
    passing = duplicate(model, deals=deals, seed=seed, workers=workers, config=config, reference="pass", field="first")
    from .learner import now
    return {"file": Path(path).name, "step": counters["steps"], "seconds": counters.get("seconds"),
            "runder": counters["runder"], "rating": rated["rating"], "rating_ci": rated["rating_ci"],
            "win": rated["win"], "win_ci": rated["win_ci"], "vs_first": rated["vs_first"],
            "vs_svaer": svaer["diff"], "vs_pass": passing["diff"], "melder": rated["melder"],
            "svaer_table_melder": svaer["net_melder"], "svaer_melder": svaer["first_melder"],
            "exchanged": svaer["exchanged"], "spil": spil, "deals": deals, "seed": seed,
            "rated_at": now(), "rating_seconds": round(time.time() - started, 1)}


def cmd_rating(args):
    from .learner import CHECKPOINT, SNAPSHOTS
    from .rating import rate, SVAER_RATING
    if args.background:
        from .actor import lower_priority
        lower_priority()
    if args.svaer:
        result = rate("svaer", spil=args.spil, seed=args.seed, workers=args.workers)
        lo, hi = result["rating_ci"]
        print(f"Svær in one seat, three FirstBots, {result['spil']} duplicate spil of 10 runder (seed {args.seed}):")
        print(f"  rating {result['rating']:+.1f} [{lo:+.1f}, {hi:+.1f}]  win share {result['win']:.1%} ± {result['win_ci']:.1%} "
              f"(raw {result['win_raw']:.1%}, FirstBot in the seat {result['first_win_raw']:.1%})")
        print(f"  vs FirstBot {result['vs_first']['mean']:+.3f} ± {result['vs_first']['ci95']:.3f} point/runde; "
              f"melder {result['melder']['share']:.1%} of runder, home {result['melder']['home']:.1%}")
        print(f"  (the scale's constant: rating.SVAER_RATING = {SVAER_RATING})")
        return 0
    directory = run_dir(args)
    try:
        cfg.check_run(directory)
    except cfg.IncompatibleRun as e:
        print(e)
        return 1
    if args.snapshot:
        files = [directory / SNAPSHOTS / args.snapshot]
    elif args.all:
        done = {e["file"] for e in read_ratings(directory)}
        files = [p for p in sorted((directory / SNAPSHOTS).glob("step_*.pt")) if p.name not in done]
    elif args.weights:
        files = [Path(args.weights)]
    else:
        files = [directory / CHECKPOINT] if not args.csv else []
    for path in files:
        if not path.exists():
            print(f"{path}: no such file")
            return 1
        entry = rate_weights(path, args.spil, args.deals, args.workers, args.seed)
        if not args.weights:
            with (directory / RATINGS).open("a") as f:
                f.write(json.dumps(entry) + "\n")
        print(f"{path.name}: " + rating_line(entry), flush=True)
    ratings = read_ratings(directory)
    if not args.background:
        if ratings:
            print(rating_table(ratings))
        elif not files:
            print("no ratings yet")
    if args.csv and ratings:
        print(f"wrote {write_csv(directory, ratings)}")
    return 0


def cmd_eval(args):
    from .actor import rules_of
    from .evaluate import duplicate, format_report
    from .learner import CHECKPOINT, SNAPSHOTS, load_weights
    if args.weights:
        path = Path(args.weights)
    elif args.snapshot:
        path = run_dir(args) / SNAPSHOTS / args.snapshot
    else:
        path = run_dir(args) / CHECKPOINT
    try:
        model, saved = load_weights(path)
    except cfg.IncompatibleRun as e:
        print(e)
        return 1
    config = cfg.Config.from_dict(saved["config"])
    print(f"{path} (step {saved['counters']['steps']}, {saved['counters']['runder']} runder)")
    report = duplicate(model, deals=args.deals, seed=args.seed, rules=rules_of(config), workers=args.workers,
                       config=config, reference=args.reference, field=args.field)
    print(format_report(report))
    return 0


def cmd_snapshots(args):
    from .learner import SNAPSHOTS
    index = run_dir(args) / SNAPSHOTS / "index.jsonl"
    if not index.exists():
        print("no snapshots yet")
        return 0
    for line in index.read_text().splitlines():
        e = json.loads(line)
        text = f"{e['file']}  steps {e['steps']}  runder {e['runder']}"
        if "eval" in e:
            d = e["eval"]["diff"]
            text += f"  vs FirstBot {d['mean']:+.2f} ± {d['ci95']:.2f} point/runde"
        print(text)
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(prog="python -m esmakker_ai.train", description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    def common(p):
        p.add_argument("--run", default="main", help="the run's name (a folder in the runs dir)")
        p.add_argument("--runs-dir", help="where runs live (default tools/esmakker_ai/runs or $ESMAKKER_RUNS)")

    p = sub.add_parser("start", help="start or resume training")
    common(p)
    p.add_argument("--config", help="a JSON file of settings (config.py) for a new run")
    p.add_argument("--set", action="append", metavar="KEY=VALUE", help="change a setting, e.g. --set actors=6")
    p.add_argument("--max-steps", type=int, help="stop after this many learner steps")
    p.add_argument("--max-minutes", type=float, help="stop after this many minutes")
    p.add_argument("--init", help="a new run starts from the net in this snapshot or checkpoint (format 2: the old input copied, the spil context at 0)")
    p.set_defaults(func=cmd_start)

    p = sub.add_parser("stop", help="ask a running training to save and stop")
    common(p)
    p.add_argument("--wait", type=float, default=180, help="seconds to wait for it")
    p.set_defaults(func=cmd_stop)

    p = sub.add_parser("status", help="show a run's progress")
    common(p)
    p.set_defaults(func=cmd_status)

    p = sub.add_parser("eval", help="same-hand duplicate against FirstBot")
    common(p)
    p.add_argument("--weights", help="a checkpoint or snapshot file (default: the run's checkpoint)")
    p.add_argument("--snapshot", help="a snapshot's file name in the run")
    p.add_argument("--deals", type=int, default=2000)
    p.add_argument("--seed", type=int, default=7)
    p.add_argument("--workers", type=int, default=1)
    p.add_argument("--reference", choices=("first", "pass", "svaer"), default="first",
                   help="who plays the measured seat instead of the net: FirstBot, PassBot (never melder) or Svær")
    p.add_argument("--field", choices=("first", "svaer"), default="first", help="the three other seats")
    p.set_defaults(func=cmd_eval)

    p = sub.add_parser("snapshots", help="list a run's numbered snapshots")
    common(p)
    p.set_defaults(func=cmd_snapshots)

    p = sub.add_parser("rating", help="rate the net on the fixed scale (0 = FirstBot), appended to ratings.jsonl")
    common(p)
    p.add_argument("--snapshot", help="a snapshot's file name in the run (default: the run's checkpoint)")
    p.add_argument("--all", action="store_true", help="every snapshot not rated yet")
    p.add_argument("--weights", help="any checkpoint or snapshot file (printed, not saved in the run)")
    p.add_argument("--svaer", action="store_true", help="rate Svær instead (the scale's second anchor)")
    p.add_argument("--spil", type=int, default=2000, help="duplicate spil of 10 runder for the rating")
    p.add_argument("--deals", type=int, default=500, help="duplicate deals for Δ vs Svær and vs PassBot")
    p.add_argument("--seed", type=int, default=11)
    p.add_argument("--workers", type=int, default=1)
    p.add_argument("--csv", action="store_true", help="also write ratings.csv (for a chart)")
    p.add_argument("--background", action="store_true", help=argparse.SUPPRESS)  # training's own, low priority
    p.set_defaults(func=cmd_rating)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
