"""Live dashboard for es-makker training.

    python server.py [--runs-dir DIR] [--run main] [--port 8765]

Reads status.json, train.log.jsonl, ratings.jsonl, ladder.jsonl,
snapshots/index.jsonl and meldinger.jsonl from the run directory and serves
them with index.html, on this machine only (127.0.0.1). It writes nothing to
the run but this: it starts meldinger.py for snapshots not yet counted (when
it runs in the esmakker_ai venv, which has torch), and its button stops the
training (POST /api/stop: the STOP file, as `train stop`) or starts it again
(POST /api/start: `train start` of the run, with its saved settings, only
when no learner of the run is alive). Anders starts and stops the night runs
with it.
"""
import argparse
import json
import os
import subprocess
import sys
import time
from http.server import HTTPServer, SimpleHTTPRequestHandler
from pathlib import Path

HERE = Path(__file__).parent
TOOL_DIR = HERE.parent / "esmakker_ai"
DEFAULT_RUNS = Path(os.environ.get("ESMAKKER_RUNS") or TOOL_DIR / "runs")
MAX_POINTS = 600
STALE_SECONDS = 60  # a learner writes status.json every 5 s; older than this and it is gone
START_GRACE_SECONDS = 600  # a start's warm-up (actors, CUDA graphs) before its first heartbeat


def training_state(run_dir, now=None):
    """"running" (a heartbeat within STALE_SECONDS), "stopping" (asked to
    stop, still beating) or "stopped"."""
    now = time.time() if now is None else now
    path = run_dir / "status.json"
    try:
        status = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return "stopped"
    alive = status.get("state") == "running" and now - float(status.get("heartbeat") or 0) < STALE_SECONDS
    if not alive:
        return "stopped"
    return "stopping" if (run_dir / "STOP").exists() else "running"


def request_stop(run_dir):
    """Asks the run's learner to save and stop (as `train stop`)."""
    if training_state(run_dir) != "running":
        return False
    (run_dir / "STOP").write_text("stop asked from the dashboard\n")
    return True


def start_command(runs_dir, run):
    """`train start` of the run: it resumes from its checkpoint with the
    settings in its config.json."""
    return [sys.executable, "-m", "esmakker_ai.train", "start", "--runs-dir", str(runs_dir), "--run", run]


class Trainer:
    """The dashboard's stop/start of the run's training."""

    def __init__(self, runs_dir, run):
        self.runs_dir, self.run, self.run_dir = runs_dir, run, runs_dir / run
        self.started = 0.0

    def state(self):
        state = training_state(self.run_dir)
        if state == "stopped" and time.time() - self.started < START_GRACE_SECONDS:
            return "starting"
        return state

    def stop(self):
        return {"ok": request_stop(self.run_dir), "state": self.state()}

    def start(self):
        state = self.state()
        if state != "stopped":
            return {"ok": False, "state": state, "why": "the training is not stopped"}
        if not (self.run_dir / "config.json").exists():
            return {"ok": False, "state": state, "why": "no such run (a new run is started from the command line)"}
        flags = 0
        if os.name == "nt":  # its own process group, no window: it lives on when the dashboard stops
            flags = subprocess.DETACHED_PROCESS | subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.CREATE_NO_WINDOW
        with (self.run_dir / "train.out.log").open("a") as out:
            subprocess.Popen(start_command(self.runs_dir, self.run), cwd=TOOL_DIR, stdout=out,
                             stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL, creationflags=flags,
                             start_new_session=os.name != "nt")
        self.started = time.time()
        return {"ok": True, "state": self.state()}


def read_jsonl(path):
    if not path.exists():
        return []
    out = []
    with path.open(encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                try:
                    out.append(json.loads(line))
                except json.JSONDecodeError:
                    pass  # a line being written right now
    return out


def thin(rows, n=MAX_POINTS):
    if len(rows) <= n:
        return rows
    step = len(rows) / n
    picked = [rows[int(i * step)] for i in range(n)]
    picked[-1] = rows[-1]
    return picked


def gpu():
    try:
        out = subprocess.run(
            ["nvidia-smi", "--query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw",
             "--format=csv,noheader,nounits"], capture_output=True, text=True, timeout=5).stdout.strip()
        name, util, used, total, temp, power = [x.strip() for x in out.split(",")]
        return {"name": name, "util": float(util), "mem_used": float(used), "mem_total": float(total),
                "temp": float(temp), "power": float(power) if power not in ("", "[N/A]") else None}
    except Exception:
        return None


def snapshot(run_dir):
    status_path = run_dir / "status.json"
    status = json.loads(status_path.read_text()) if status_path.exists() else None
    log = read_jsonl(run_dir / "train.log.jsonl")
    progress = []
    for e in log:
        if e.get("event") != "progress":
            continue
        c, r, l = e["counters"], e.get("rates", {}), e.get("losses", {})
        progress.append({"t": c.get("seconds"), "steps": c.get("steps"), "runder": c.get("runder"),
                         "runder_s": r.get("runder_per_s"), "steps_s": r.get("steps_per_s"),
                         "loss": l.get("loss"), "q": l.get("q"), "value": l.get("value")})
    events = [{"at": e["at"], "event": e["event"], "steps": e.get("counters", {}).get("steps", e.get("steps"))}
              for e in log if e.get("event") in ("start", "stop", "checkpoint")]
    ratings = [{"file": e["file"], "step": e["step"], "t": e.get("seconds"), "rating": e["rating"],
                "lo": e["rating_ci"][0], "hi": e["rating_ci"][1],
                "svaer": e["vs_svaer"]["mean"], "svaer_ci": e["vs_svaer"]["ci95"],
                "pass": e["vs_pass"]["mean"], "pass_ci": e["vs_pass"]["ci95"]}
               for e in read_jsonl(run_dir / "ratings.jsonl")]
    snaps = [{"file": e["file"], "step": e["steps"], "first": e["eval"]["diff"]["mean"],
              "first_ci": e["eval"]["diff"]["ci95"]}
             for e in read_jsonl(run_dir / "snapshots" / "index.jsonl") if "eval" in e]
    # one count per snapshot, the newest (a count made again is appended)
    meldinger = sorted({e["file"]: e for e in read_jsonl(run_dir / "meldinger.jsonl")}.values(), key=lambda e: e["step"])
    ladder = [{k: e[k] for k in ("file", "step", "vs", "vs_step", "kind", "mode", "diff", "runder", "significant",
                                 "worse_significant")}
              for e in read_jsonl(run_dir / "ladder.jsonl")]
    return {"run": run_dir.name, "status": status, "progress": thin(progress), "events": events[-50:],
            "ratings": sorted(ratings, key=lambda r: r["step"]), "snapshots": snaps, "meldinger": meldinger,
            "ladder": ladder, "gpu": gpu()}


class MeldingCounter:
    """Runs meldinger.py in the background when a snapshot has no count yet."""

    def __init__(self, runs_dir, run):
        self.runs_dir, self.run, self.job = runs_dir, run, None
        try:
            import torch  # noqa: F401  the count plays with the net
            self.able = True
        except ImportError:
            self.able = False

    def poke(self, data):
        if not self.able or (self.job and self.job.poll() is None):
            return
        counted = {e["file"] for e in data["meldinger"] if "guess" in e and "self_deals" in e
                   and ("contract" not in e["guess"] or "ce" in e["guess"]["contract"])}
        if any(s["file"] not in counted for s in data["snapshots"]):
            flags = getattr(subprocess, "BELOW_NORMAL_PRIORITY_CLASS", 0)
            self.job = subprocess.Popen([sys.executable, str(HERE / "meldinger.py"), "--run", self.run,
                                         "--runs-dir", str(self.runs_dir)], creationflags=flags,
                                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--runs-dir", type=Path, default=DEFAULT_RUNS)
    ap.add_argument("--run", default="main")
    ap.add_argument("--port", type=int, default=8765)
    args = ap.parse_args()
    run_dir = args.runs_dir / args.run
    counter = MeldingCounter(args.runs_dir, args.run)
    trainer = Trainer(args.runs_dir, args.run)
    make_server(run_dir, counter, trainer, args.port).serve_forever()


def make_server(run_dir, counter, trainer, port):
    class Handler(SimpleHTTPRequestHandler):
        def __init__(self, *a, **kw):
            super().__init__(*a, directory=str(HERE), **kw)

        def log_message(self, *a):
            pass

        def send_json(self, data, code=200):
            body = json.dumps(data).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            if self.path.startswith("/api/data"):
                data = snapshot(run_dir)
                data["training"] = trainer.state()
                if counter is not None:
                    counter.poke(data)
                self.send_json(data)
            else:
                super().do_GET()

        def do_POST(self):
            # the page's own fetch sends this header; a form on another site cannot
            if self.headers.get("X-Esmakker") != "1":
                self.send_json({"ok": False, "why": "forbidden"}, 403)
            elif self.path == "/api/stop":
                self.send_json(trainer.stop())
            elif self.path == "/api/start":
                self.send_json(trainer.start())
            else:
                self.send_json({"ok": False, "why": "no such action"}, 404)

    server = HTTPServer(("127.0.0.1", port), Handler)
    print(f"dashboard on http://localhost:{server.server_address[1]}  (run dir {run_dir})", flush=True)
    return server


if __name__ == "__main__":
    main()
