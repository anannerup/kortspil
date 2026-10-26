"""Training settings: defaults here, a JSON file (`--config`) over them,
CLI flags (`--set key=value`) over that. A run keeps its settings in
<run dir>/config.json; a resumed run reads them from there.
"""

import json
import os
from dataclasses import asdict, dataclass, fields
from pathlib import Path

TOOL_DIR = Path(__file__).resolve().parent.parent
DEFAULT_RUNS = TOOL_DIR / "runs"  # gitignored


@dataclass
class Config:
    seed: int = 1
    device: str = "auto"              # auto: cuda, then mps, then cpu
    actors: int = 4                   # self-play processes on the CPU; 0 plays in the learner (tests)
    # the net
    hidden: int = 512
    action_hidden: int = 128
    points_scale: float = 10.0        # the Q and value heads learn points / points_scale
    # self-play
    epsilon: float = 0.03             # share of random choices while playing
    bid_epsilon: float = 0.1          # ... in the meldingsrunde: pas or one of the 3 lowest meldinger
    partner_share: float = 0.25       # share of games with the partner bot on the three other seats
    partner: str = "svaer"            # partners.py: "svaer" (strategy §6) or "first"
    rules: dict = None                # Rules.from_dict; None is the standard bord
    # the learner
    batch_size: int = 1024
    lr: float = 2e-4
    grad_clip: float = 40.0
    replay_size: int = 300_000        # samples kept (bit-packed, ~200 bytes each)
    min_replay: int = 20_000          # samples before the learner starts
    max_reuse: float = 4.0            # at most this many trained samples per generated sample
    stik_weight: float = 0.5          # loss weights of the extra heads
    makker_weight: float = 0.5
    value_weight: float = 0.5
    # sync mode (actors = 0): runder played, then learner steps, per round of work
    sync_runder: int = 8
    sync_updates: int = 2
    # bookkeeping
    weights_every: int = 50           # learner steps between weight copies to the actors
    checkpoint_minutes: float = 10.0  # full checkpoint (resume point) at this interval
    checkpoint_steps: int = 0         # ... or every so many learner steps (0: off)
    snapshot_steps: int = 20_000      # numbered weight snapshots (for picking Let/Mellem)
    snapshot_eval_deals: int = 200    # quick duplicate eval vs FirstBot at each snapshot (0: off)
    low_priority: bool = True         # lower the process priority (CPU only; see README)

    @classmethod
    def from_dict(cls, values):
        known = {f.name for f in fields(cls)}
        unknown = set(values) - known
        if unknown:
            raise ValueError(f"unknown settings {sorted(unknown)}")
        return cls(**values)

    def to_dict(self):
        return asdict(self)

    def override(self, pairs):
        """`key=value` strings, the value read as JSON when it parses."""
        types = {f.name: f.type for f in fields(self)}
        for pair in pairs or ():
            key, _, text = pair.partition("=")
            if key not in types:
                raise ValueError(f"unknown setting {key!r}")
            try:
                value = json.loads(text)
            except json.JSONDecodeError:
                value = text
            setattr(self, key, value)
        return self


def runs_root(path=None):
    return Path(path or os.environ.get("ESMAKKER_RUNS") or DEFAULT_RUNS)


def save(config, path):
    Path(path).write_text(json.dumps(config.to_dict(), indent=2) + "\n")


def load(path):
    return Config.from_dict(json.loads(Path(path).read_text()))
