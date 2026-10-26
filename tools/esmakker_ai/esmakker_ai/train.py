"""Training commands (run from tools/esmakker_ai):

    python -m esmakker_ai.train start  [--run NAME] [--config FILE] [--set key=value ...]
    python -m esmakker_ai.train stop   [--run NAME]
    python -m esmakker_ai.train status [--run NAME]
    python -m esmakker_ai.train eval   [--run NAME | --weights FILE] [--deals N] [--seed S] [--workers W]
    python -m esmakker_ai.train snapshots [--run NAME]

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
    train(config, directory, max_steps=args.max_steps, max_seconds=args.max_minutes * 60 if args.max_minutes else None)
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
    model, saved = load_weights(path)
    config = cfg.Config.from_dict(saved["config"])
    print(f"{path} (step {saved['counters']['steps']}, {saved['counters']['runder']} runder)")
    report = duplicate(model, deals=args.deals, seed=args.seed, rules=rules_of(config), workers=args.workers,
                       config=config)
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
    p.set_defaults(func=cmd_eval)

    p = sub.add_parser("snapshots", help="list a run's numbered snapshots")
    common(p)
    p.set_defaults(func=cmd_snapshots)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
