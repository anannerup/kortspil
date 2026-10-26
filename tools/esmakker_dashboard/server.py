"""Live dashboard for es-makker training.

    python server.py [--runs-dir DIR] [--run main] [--port 8765]

Reads status.json, train.log.jsonl, ratings.jsonl and snapshots/index.jsonl
from the run directory and serves them with index.html. Read-only.
"""
import argparse
import json
import os
import subprocess
from http.server import HTTPServer, SimpleHTTPRequestHandler
from pathlib import Path

HERE = Path(__file__).parent
DEFAULT_RUNS = Path(os.environ.get("ESMAKKER_RUNS") or HERE.parent / "esmakker_ai" / "runs")
MAX_POINTS = 600


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
    return {"run": run_dir.name, "status": status, "progress": thin(progress), "events": events[-50:],
            "ratings": sorted(ratings, key=lambda r: r["step"]), "snapshots": snaps, "gpu": gpu()}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--runs-dir", type=Path, default=DEFAULT_RUNS)
    ap.add_argument("--run", default="main")
    ap.add_argument("--port", type=int, default=8765)
    args = ap.parse_args()
    run_dir = args.runs_dir / args.run

    class Handler(SimpleHTTPRequestHandler):
        def __init__(self, *a, **kw):
            super().__init__(*a, directory=str(HERE), **kw)

        def log_message(self, *a):
            pass

        def do_GET(self):
            if self.path.startswith("/api/data"):
                body = json.dumps(snapshot(run_dir)).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Cache-Control", "no-store")
                self.end_headers()
                self.wfile.write(body)
            else:
                super().do_GET()

    print(f"dashboard on http://localhost:{args.port}  (run dir {run_dir})", flush=True)
    HTTPServer(("0.0.0.0", args.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
