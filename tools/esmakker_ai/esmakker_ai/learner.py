"""The learner: a replay buffer, the training step, checkpoints, and the
training loop (actor processes feeding it, or sync mode with no actors).

A checkpoint is the full resume point: the net, the optimizer, the replay
buffer, every RNG and the counters. In sync mode (actors = 0) a resumed run
continues exactly as if it had never stopped (tests/test_training.py). With
actor processes the deals and the order samples arrive in depend on timing;
a resumed run gets the same net, optimizer, buffer and counters, and its
actors are seeded anew from (seed, resume count, actor).
"""

import json
import os
import random
import time
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import torch
import torch.nn.functional as TF

from . import features as F
from .actor import Batch, actor_main, lower_priority, play_game, rules_of
from .agent import ACTION_TABLE, Q_TARGET, TARGETS, WIN_TARGET
from .config import Config, check_run, incompatible
from .net import build, pick_device, unpack_bits
from .partners import factory
from .search import enabled as search_enabled, play_searched

CHECKPOINT = "checkpoint.pt"
STATUS = "status.json"
STOP = "STOP"
LOG = "train.log.jsonl"
SNAPSHOTS = "snapshots"
HEARTBEAT_SECONDS = 5


def now():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def free_memory_gb():
    """(free RAM, free commit: RAM plus page file) of the machine in GB, or
    None where it cannot be read. On Windows a full commit is what took the
    PC down on 27 October 2026 (bugcheck 0x154 while paging), so training
    stops before it gets there."""
    if os.name == "nt":
        import ctypes

        class Status(ctypes.Structure):
            _fields_ = [("length", ctypes.c_ulong), ("load", ctypes.c_ulong),
                        ("total_phys", ctypes.c_ulonglong), ("avail_phys", ctypes.c_ulonglong),
                        ("total_commit", ctypes.c_ulonglong), ("avail_commit", ctypes.c_ulonglong),
                        ("total_virtual", ctypes.c_ulonglong), ("avail_virtual", ctypes.c_ulonglong),
                        ("avail_extended", ctypes.c_ulonglong)]

        status = Status(length=ctypes.sizeof(Status))
        if not ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(status)):
            return None
        return status.avail_phys / 2**30, status.avail_commit / 2**30
    try:
        pages, size = os.sysconf("SC_AVPHYS_PAGES"), os.sysconf("SC_PAGE_SIZE")
    except (ValueError, OSError, AttributeError):
        return None
    free = pages * size / 2**30
    return free, free


def previous(path):
    """Where the checkpoint before `path` is kept (Trainer.save)."""
    return Path(path).with_name(Path(path).stem + ".prev" + Path(path).suffix)


class Replay:
    """A ring buffer of samples: state bits packed, the action id, targets."""

    def __init__(self, size):
        self.size = size
        self.states = np.zeros((size, F.STATE_BYTES), np.uint8)
        self.actions = np.zeros(size, np.int16)
        self.targets = np.zeros((size, TARGETS), np.float32)
        self.weights = np.ones((size, 2), np.float32)  # the Q loss's and the other heads' (search.py)
        self.weighted = False  # a row with weights other than (1, 1) was ever added
        self.pos = 0
        self.count = 0

    def add(self, states, actions, targets, weights=None):
        n = len(actions)
        if weights is None:
            weights = np.ones((n, 2), np.float32)
        elif (weights != 1).any():
            self.weighted = True
        if n >= self.size:
            states, actions, targets, weights = (states[-self.size:], actions[-self.size:], targets[-self.size:],
                                                 weights[-self.size:])
            n = self.size
        end = self.pos + n
        columns = (self.states, self.actions, self.targets, self.weights)
        values = (states, actions, targets, weights)
        if end <= self.size:
            for column, value in zip(columns, values):
                column[self.pos:end] = value
        else:
            first = self.size - self.pos
            for column, value in zip(columns, values):
                column[self.pos:] = value[:first]
                column[:n - first] = value[first:]
        self.pos = end % self.size
        self.count = min(self.size, self.count + n)

    def state_dict(self):
        n = self.count
        return {"size": self.size, "pos": self.pos, "count": n, "states": torch.from_numpy(self.states[:n].copy()),
                "actions": torch.from_numpy(self.actions[:n].copy()), "targets": torch.from_numpy(self.targets[:n].copy()),
                "weights": torch.from_numpy(self.weights[:n].copy()), "weighted": self.weighted}

    def load_state_dict(self, d):
        if d["size"] != self.size:
            raise ValueError(f"the checkpoint's replay holds {d['size']}, the config says {self.size}")
        n = d["count"]
        self.states[:n], self.actions[:n], self.targets[:n] = d["states"].numpy(), d["actions"].numpy(), d["targets"].numpy()
        self.weights[:n] = d["weights"].numpy() if "weights" in d else 1.0
        self.weighted = d.get("weighted", False)
        self.pos, self.count = d["pos"], n


class Trainer:
    def __init__(self, config, device=None):
        self.config = config
        self.device = device or pick_device(config.device)
        torch.manual_seed(config.seed)
        self.model = build(config).to(self.device)
        self.optimizer = torch.optim.Adam(self.model.parameters(), lr=config.lr)
        self.replay = Replay(config.replay_size)
        self.action_table = torch.from_numpy(ACTION_TABLE).to(self.device)
        self.np_rng = np.random.default_rng(config.seed)
        self.play_rng = random.Random(config.seed)  # sync mode's self-play
        self.counters = {"steps": 0, "samples": 0, "runder": 0, "spil": 0, "resumes": 0, "trained": 0, "seconds": 0.0}
        if search_enabled(config):
            self.counters["searched"] = 0
        self.snapshots = []
        self.last_losses = {}

    # -- data ------------------------------------------------------------

    def add(self, states, actions, targets, runder, spil=0, weights=None, searched=0):
        self.replay.add(states, actions, targets, weights)
        self.counters["samples"] += len(actions)
        self.counters["runder"] += runder
        self.counters["spil"] = self.counters.get("spil", 0) + spil
        if searched:
            self.counters["searched"] = self.counters.get("searched", 0) + searched

    def ready(self):
        c = self.config
        return (self.replay.count >= c.min_replay
                and self.counters["trained"] < c.max_reuse * self.counters["samples"])

    # -- the training step -------------------------------------------------

    def train_step(self):
        c = self.config
        idx = self.np_rng.integers(0, self.replay.count, c.batch_size)
        dev = self.device
        states = unpack_bits(torch.from_numpy(self.replay.states[idx]).to(dev))
        actions = self.action_table[torch.from_numpy(self.replay.actions[idx].astype(np.int64)).to(dev)]
        t = torch.from_numpy(self.replay.targets[idx]).to(dev)
        q, heads = self.model(states, actions)
        scale = self.model.points_scale
        q_target, points = t[:, Q_TARGET] / scale, t[:, 0] / scale
        own_mask, makker_mask = t[:, 4], t[:, 5]
        called = 1 - states[:, F.CALLED + 4]  # the ace is called in this state
        win = t[:, WIN_TARGET]
        if self.replay.weighted:
            # search rows (search.py): the Q loss weighted, the other heads not trained on them
            w = torch.from_numpy(self.replay.weights[idx]).to(dev)
            q_loss = (w[:, 0] * (q - q_target) ** 2).mean()
            aux = w[:, 1]
            norm = aux.sum().clamp(min=1)
            value_loss = (aux * (heads["value"] - points) ** 2).sum() / norm
            win_loss = (aux * TF.binary_cross_entropy_with_logits(heads["win"], win, reduction="none")).sum() / norm
            own_mask, makker_mask, called = own_mask * aux, makker_mask * aux, called * aux
        else:
            q_loss = TF.mse_loss(q, q_target)
            value_loss = TF.mse_loss(heads["value"], points)
            win_loss = TF.binary_cross_entropy_with_logits(heads["win"], win)
        own_loss = (((heads["stik"][:, 0] - t[:, 1]) / 13) ** 2 * own_mask).sum() / own_mask.sum().clamp(min=1)
        mk_stik_loss = (((heads["stik"][:, 1] - t[:, 2]) / 13) ** 2 * makker_mask).sum() / makker_mask.sum().clamp(min=1)
        ce = TF.cross_entropy(heads["makker"], t[:, 3].long(), reduction="none")
        makker_loss = (ce * called).sum() / called.sum().clamp(min=1)
        loss = (q_loss + c.value_weight * value_loss + c.stik_weight * (own_loss + mk_stik_loss)
                + c.makker_weight * makker_loss + c.win_weight * win_loss)
        self.optimizer.zero_grad(set_to_none=True)
        loss.backward()
        torch.nn.utils.clip_grad_norm_(self.model.parameters(), c.grad_clip)
        self.optimizer.step()
        self.counters["steps"] += 1
        self.counters["trained"] += c.batch_size
        self.last_losses = {"loss": loss.item(), "q": q_loss.item(), "value": value_loss.item(),
                            "own_stik": own_loss.item(), "makker_stik": mk_stik_loss.item(),
                            "makker": makker_loss.item(), "win": win_loss.item()}
        return self.last_losses

    # -- sync mode -----------------------------------------------------------

    def sync_round(self):
        """Plays whole spil with the current net until sync_runder runder
        (at least one spil), then up to sync_updates learner steps.
        Deterministic for a seed on the CPU."""
        c = self.config
        model = self.cpu_copy()
        batch = Batch()
        partner = factory(c.partner)
        rules = rules_of(c)
        if search_enabled(c):
            play_searched(model, self.play_rng, c, partner, rules, batch, c.sync_runder)
        else:
            while batch.runder < c.sync_runder:
                play_game(model, self.play_rng, c, partner, rules, batch)
        if len(batch):
            states, actions, targets, weights = batch.arrays()
            self.add(states, actions, targets, batch.runder, batch.spil, weights, batch.searched)
        else:
            self.counters["runder"] += batch.runder
            self.counters["spil"] += batch.spil
        for _ in range(c.sync_updates):
            if self.ready():
                self.train_step()

    def cpu_copy(self):
        model = build(self.config)
        model.load_state_dict({k: v.detach().cpu() for k, v in self.model.state_dict().items()})
        model.eval()
        return model

    # -- checkpoints ---------------------------------------------------------

    def state_dict(self):
        return {
            "format": F.FORMAT,
            "config": self.config.to_dict(),
            "model": self.model.state_dict(),
            "optimizer": self.optimizer.state_dict(),
            "replay": self.replay.state_dict(),
            "np_rng": self.np_rng.bit_generator.state,
            "play_rng": self.play_rng.getstate(),
            "torch_rng": torch.get_rng_state(),
            "counters": dict(self.counters),
            "snapshots": list(self.snapshots),
            "saved_at": now(),
        }

    def load_state_dict(self, d):
        if d.get("format") != F.FORMAT:
            raise incompatible("the checkpoint", d.get("format"))
        self.model.load_state_dict(d["model"])
        self.optimizer.load_state_dict(d["optimizer"])
        for group in self.optimizer.param_groups:  # a changed lr (--set lr=...) applies on resume
            group["lr"] = self.config.lr
        self.replay.load_state_dict(d["replay"])
        self.np_rng.bit_generator.state = d["np_rng"]
        self.play_rng.setstate(d["play_rng"])
        torch.set_rng_state(d["torch_rng"])
        self.counters = dict(d["counters"])
        self.snapshots = list(d["snapshots"])

    def save(self, path):
        path = Path(path)
        tmp = path.with_name(path.name + ".tmp")
        with open(tmp, "wb") as f:
            torch.save(self.state_dict(), f)
            # on disk before the replace: a crash right after it (the PC did,
            # 27 October 2026) otherwise leaves a checkpoint of zeros
            f.flush()
            os.fsync(f.fileno())
        if path.exists():
            os.replace(path, previous(path))  # the last good one, should this one break
        os.replace(tmp, path)

    def load(self, path):
        # on the CPU: the replay and RNG states must stay there; the model and the
        # optimizer copy theirs to the device as they load
        try:
            state = torch.load(path, map_location="cpu", weights_only=False)
        except Exception:
            if not previous(path).exists():
                raise
            print(f"{path} does not load; resuming from {previous(path).name}", flush=True)
            state = torch.load(previous(path), map_location="cpu", weights_only=False)
        self.load_state_dict(state)

    def save_snapshot(self, run_dir):
        folder = Path(run_dir) / SNAPSHOTS
        folder.mkdir(parents=True, exist_ok=True)
        name = f"step_{self.counters['steps']:09d}.pt"
        torch.save({"format": F.FORMAT, "config": self.config.to_dict(), "model": self.cpu_copy().state_dict(),
                    "counters": dict(self.counters), "saved_at": now()}, folder / name)
        return folder / name


def load_weights(path):
    """A snapshot or a checkpoint as a CPU model ready to play."""
    d = torch.load(path, map_location="cpu", weights_only=False)
    if d.get("format") != F.FORMAT:
        raise incompatible(str(path), d.get("format"))
    config = Config.from_dict(d["config"])
    model = build(config)
    model.load_state_dict({k: v.cpu() for k, v in d["model"].items()})
    model.eval()
    return model, d


def warm_start(model, path):
    """Starts `model` from the net in a snapshot or checkpoint: every weight
    of the same shape is copied. From FORMAT 2 (the same layout without the
    spil context at the end) the first layer's columns for the old input are
    copied and those for the new input set to 0, so the net starts out
    choosing exactly as the old one, blind to the spil until it learns it; a
    head the old net lacked (the spil win) keeps its fresh weights. Returns
    lines to report."""
    d = torch.load(path, map_location="cpu", weights_only=False)
    found = d.get("format")
    old_bits = {F.FORMAT: F.STATE_BITS, 2: F.FORMAT2_STATE_BITS}.get(found)
    if old_bits is None:
        raise incompatible(str(path), found)
    old = d["model"]
    new = model.state_dict()
    fresh = []
    with torch.no_grad():
        for name, value in new.items():
            if name not in old:
                fresh.append(name)
                continue
            source = old[name].to(value.device, value.dtype)
            if source.shape == value.shape:
                value.copy_(source)
            elif name == "state.0.weight" and source.shape == (value.shape[0], old_bits):
                value.zero_()
                value[:, :old_bits] = source
            else:
                raise ValueError(f"{path}: {name} is {tuple(source.shape)}, this net's is {tuple(value.shape)} "
                                 f"(start with the old net's hidden sizes)")
    lines = [f"new run from the net in {path} (format {found})"]
    if found != F.FORMAT:
        lines.append(f"  input {old_bits} -> {F.STATE_BITS} bits: the new columns start at 0")
    if fresh:
        lines.append(f"  fresh: {', '.join(sorted({n.split('.')[0] for n in fresh}))}")
    return lines


# -- the training loop -----------------------------------------------------------


class Run:
    """A run directory: config.json, checkpoint.pt, snapshots/, status.json,
    train.log.jsonl, and STOP while a stop is asked for."""

    def __init__(self, run_dir):
        self.dir = Path(run_dir)

    def path(self, name):
        return self.dir / name

    def status(self):
        try:
            return json.loads(self.path(STATUS).read_text())
        except (FileNotFoundError, json.JSONDecodeError):
            return None

    def write_status(self, **fields):
        tmp = self.path(STATUS + ".tmp")
        tmp.write_text(json.dumps(fields, indent=2) + "\n")
        # Windows refuses the replace while a reader (the dashboard) has the
        # file open; it is only a status, so try a few times, then skip it
        for attempt in range(5):
            try:
                os.replace(tmp, self.path(STATUS))
                return
            except PermissionError:
                time.sleep(0.05 * (attempt + 1))

    def log(self, **fields):
        with self.path(LOG).open("a") as f:
            f.write(json.dumps({"at": now(), **fields}) + "\n")

    def running(self):
        """Running when the status heartbeat is fresh."""
        status = self.status()
        if not status or status.get("state") != "running":
            return False
        return time.time() - status.get("heartbeat", 0) < 6 * HEARTBEAT_SECONDS


def _echo(text):
    print(text, flush=True)


def train(config, run_dir, max_steps=None, max_seconds=None, echo=_echo, init=None):
    """Trains until stopped (Ctrl+C, `train stop`, or max_steps/max_seconds),
    resuming from the run's checkpoint when there is one. A new run may start
    from the net of a snapshot or checkpoint (`init`), with fresh replay,
    optimizer and counters."""
    run = Run(run_dir)
    check_run(run.dir)
    run.dir.mkdir(parents=True, exist_ok=True)
    if config.low_priority:
        lower_priority()
    trainer = Trainer(config)
    checkpoint = run.path(CHECKPOINT)
    if checkpoint.exists():
        trainer.load(checkpoint)
        trainer.counters["resumes"] += 1
        echo(f"resumed at step {trainer.counters['steps']}, {trainer.counters['runder']} runder, "
             f"replay {trainer.replay.count}")
    elif init:
        for line in warm_start(trainer.model, init):
            echo(line)
    else:
        echo("new run")
    run.path(STOP).unlink(missing_ok=True)
    echo(f"device {trainer.device}, {config.actors} actors, run dir {run.dir}")
    run.log(event="start", device=str(trainer.device), counters=trainer.counters, config=config.to_dict())

    loop = _ActorLoop(trainer, config) if config.actors > 0 else None
    started = time.time()
    last_checkpoint = time.time()
    last_status = 0.0
    rate_mark = (time.time(), trainer.counters["samples"], trainer.counters["runder"], trainer.counters["steps"])
    rates = {}
    searched_mark = trainer.counters.get("searched", 0)
    reason = "stopped"
    steps_at_start = trainer.counters["steps"]
    seconds_at_start = trainer.counters.setdefault("seconds", 0.0)
    rater = _Rater(run, config)

    def clock():
        trainer.counters["seconds"] = round(seconds_at_start + time.time() - started, 1)

    def status(state):
        run.write_status(state=state, pid=os.getpid(), heartbeat=time.time(), updated=now(),
                         device=str(trainer.device), actors=config.actors, counters=trainer.counters,
                         replay=trainer.replay.count, rates=rates, losses=trainer.last_losses,
                         last_checkpoint=str(checkpoint) if checkpoint.exists() else None,
                         snapshots=trainer.snapshots[-3:])

    next_memory_check = 0.0
    try:
        if loop:
            loop.start()
        while True:
            if run.path(STOP).exists():
                reason = "stop asked"
                break
            if max_steps is not None and trainer.counters["steps"] - steps_at_start >= max_steps:
                reason = "max steps"
                break
            if max_seconds is not None and time.time() - started >= max_seconds:
                reason = "max time"
                break
            if time.time() >= next_memory_check:
                next_memory_check = time.time() + 5
                free = free_memory_gb()
                if free is not None and min(free) < config.min_free_memory_gb:
                    reason = f"low memory ({free[0]:.1f} GB RAM, {free[1]:.1f} GB commit free; fewer actors?)"
                    break
            clock()
            step_before = trainer.counters["steps"]
            if loop:
                loop.drain(block=not trainer.ready())
                if trainer.ready():
                    trainer.train_step()
                    if trainer.counters["steps"] % config.weights_every == 0:
                        loop.publish()
            else:
                trainer.sync_round()
            steps = trainer.counters["steps"]
            stepped = steps != step_before
            if stepped and config.snapshot_steps and steps % config.snapshot_steps == 0:
                _snapshot(trainer, run, echo)
                rater.rate_new()
            if stepped and config.checkpoint_steps and steps % config.checkpoint_steps == 0:
                trainer.save(checkpoint)
                last_checkpoint = time.time()
            if time.time() - last_checkpoint >= config.checkpoint_minutes * 60:
                trainer.save(checkpoint)
                last_checkpoint = time.time()
                run.log(event="checkpoint", counters=trainer.counters)
            if time.time() - last_status >= HEARTBEAT_SECONDS:
                t0, s0, r0, st0 = rate_mark
                dt = max(time.time() - t0, 1e-9)
                c = trainer.counters
                rates = {"samples_per_s": round((c["samples"] - s0) / dt, 1),
                         "runder_per_s": round((c["runder"] - r0) / dt, 2),
                         "steps_per_s": round((c["steps"] - st0) / dt, 2)}
                if "searched" in c:
                    rates["searched_per_s"] = round((c["searched"] - searched_mark) / dt, 2)
                    searched_mark = c["searched"]
                rate_mark = (time.time(), c["samples"], c["runder"], c["steps"])
                status("running")
                if last_status:
                    echo(f"step {c['steps']}  runder {c['runder']}  samples {c['samples']}  "
                         f"replay {trainer.replay.count}  {rates['runder_per_s']} runder/s  "
                         f"{rates['steps_per_s']} steps/s  "
                         + (f"{rates['searched_per_s']} searched/s  " if "searched_per_s" in rates else "")
                         + f"loss {trainer.last_losses.get('loss', float('nan')):.4f}")
                    run.log(event="progress", counters=c, rates=rates, losses=trainer.last_losses)
                last_status = time.time()
    except KeyboardInterrupt:
        reason = "Ctrl+C"
    finally:
        echo(f"{reason}: saving the checkpoint ...")
        clock()
        trainer.save(checkpoint)  # before stopping the actors, so a stop that hangs cannot lose it
        if loop:
            loop.stop()
        run.path(STOP).unlink(missing_ok=True)
        status("stopped")
        run.log(event="stop", reason=reason, counters=trainer.counters)
        echo(f"saved {checkpoint} at step {trainer.counters['steps']}")
    return trainer


def _snapshot(trainer, run, echo):
    path = trainer.save_snapshot(run.dir)
    entry = {"file": path.name, "steps": trainer.counters["steps"], "runder": trainer.counters["runder"]}
    if trainer.config.snapshot_eval_deals:
        from .evaluate import duplicate
        report = duplicate(trainer.cpu_copy(), deals=trainer.config.snapshot_eval_deals, seed=999,
                           rules=rules_of(trainer.config))
        entry["eval"] = {k: report[k] for k in ("net", "first", "diff")}
    trainer.snapshots.append(entry)
    run.log(event="snapshot", **entry)
    with (run.dir / SNAPSHOTS / "index.jsonl").open("a") as f:
        f.write(json.dumps(entry) + "\n")
    echo(f"snapshot {path.name}" + (f"  vs FirstBot {entry['eval']['diff']['mean']:+.2f} "
                                     f"± {entry['eval']['diff']['ci95']:.2f} point/runde" if "eval" in entry else ""))


class _Rater:
    """Rates new snapshots in a background process at low priority
    (`train rating --all`, rating.py), so the learner does not wait. One
    at a time: a snapshot made while one is being rated is picked up by the
    next (or by `train rating --all`)."""

    def __init__(self, run, config):
        self.run = run
        self.config = config
        self.process = None

    def rate_new(self):
        if not self.config.rating_spil or (self.process and self.process.poll() is None):
            return
        import subprocess
        import sys
        from .config import TOOL_DIR
        command = [sys.executable, "-m", "esmakker_ai.train", "rating", "--all", "--background",
                   "--runs-dir", str(self.run.dir.parent), "--run", self.run.dir.name,
                   "--spil", str(self.config.rating_spil), "--deals", str(self.config.rating_deals)]
        with self.run.path("rating.log").open("a") as out:
            self.process = subprocess.Popen(command, cwd=TOOL_DIR, stdout=out, stderr=subprocess.STDOUT,
                                            stdin=subprocess.DEVNULL)


class _ActorLoop:
    """Actor processes (CPU) and the queue they fill."""

    def __init__(self, trainer, config):
        import torch.multiprocessing as mp
        self.mp = mp.get_context("spawn")
        self.trainer = trainer
        self.config = config
        self.shared = build(config)
        self.shared.load_state_dict(trainer.cpu_copy().state_dict())
        self.shared.share_memory()
        self.version = self.mp.Value("q", 0)
        self.lock = self.mp.Lock()
        self.queue = self.mp.Queue(maxsize=4 * config.actors)
        self.stop_event = self.mp.Event()
        self.processes = []

    def start(self):
        c = self.trainer.counters
        for i in range(self.config.actors):
            seed = hash((self.config.seed, c["resumes"], i)) & 0x7FFFFFFF
            p = self.mp.Process(target=actor_main, daemon=True,
                                args=(i, self.config, self.shared, self.version, self.lock, self.queue,
                                      self.stop_event, seed))
            p.start()
            self.processes.append(p)

    def publish(self):
        with self.lock, torch.no_grad():
            for name, value in self.trainer.model.state_dict().items():
                self.shared.state_dict()[name].copy_(value.detach().cpu())
            self.version.value += 1

    def drain(self, block):
        import queue as queue_module
        got = 0
        while got < 2 * self.config.actors:
            try:
                message = self.queue.get(timeout=0.2) if (block and not got) else self.queue.get_nowait()
            except queue_module.Empty:
                break
            _, states, actions, targets, weights, runder, spil, searched = message
            self.trainer.add(states, actions, targets, runder, spil, weights, searched)
            got += 1
        return got

    def stop(self):
        self.stop_event.set()
        deadline = time.time() + 15
        # the actors put with a timeout and see the stop; reading the queue here could block for
        # good on a message an exiting actor left half-written
        while any(p.is_alive() for p in self.processes) and time.time() < deadline:
            time.sleep(0.1)
        for p in self.processes:
            if p.is_alive():
                p.terminate()
            p.join(timeout=5)
