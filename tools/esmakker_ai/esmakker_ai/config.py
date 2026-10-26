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
    actor_device: str = "cpu"         # where the actors run the net: cpu, cuda, or auto (as device)
    actor_games: int = 1              # runder each actor plays at once, their decisions scored in one batch
    # the net
    hidden: int = 512
    action_hidden: int = 128
    points_scale: float = 10.0        # the Q and value heads learn points / points_scale
    # self-play
    epsilon: float = 0.03             # share of random choices while playing
    bid_epsilon: float = 0.1          # ... in the meldingsrunde: pas or one of the 3 lowest meldinger
    partner_share: float = 0.25       # share of games with the partner bot on the three other seats
    partner: str = "svaer"            # partners.py: "svaer" (strategy §6) or "first"
    # no rules setting: training plays only the house rules (REGLER §2.0, rules.STANDARD; Anders:
    # "hvis man spiller med bots spiller man med husets regler")
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
    rating_spil: int = 400            # each snapshot is rated in a background process (rating.py; 0: off) ...
    rating_deals: int = 200           # ... with this many duplicate deals for Δ vs Svær and vs PassBot
    low_priority: bool = True         # lower the process priority (CPU only; see README)

    @classmethod
    def from_dict(cls, values):
        values = {k: v for k, v in values.items() if k != "format"}
        if values.get("rules") is not None:
            raise ValueError("training plays only the house rules; the setting 'rules' is gone")
        values.pop("rules", None)
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
    from .features import FORMAT
    Path(path).write_text(json.dumps({"format": FORMAT, **config.to_dict()}, indent=2) + "\n")


def load(path):
    return Config.from_dict(json.loads(Path(path).read_text()))


class IncompatibleRun(Exception):
    """A run (or weights file) made for another FORMAT of the net's input."""


def incompatible(where, found):
    from .features import FORMAT
    return IncompatibleRun(
        f"{where} was made for format {found or 1} of the net's input and actions; this code is format {FORMAT} "
        f"(the net now chooses how many cards to exchange, sees the exchange counts, and may lay fordækt "
        f"out of turn). It cannot be resumed or loaded: start a new run with --run NAME "
        f"(e.g. --run main{FORMAT}), or check out the older code to use it.")


def check_run(run_dir):
    """Raises IncompatibleRun when the run directory's config.json is of
    another FORMAT (written before FORMAT was saved: format 1)."""
    from .features import FORMAT
    path = Path(run_dir) / "config.json"
    if not path.exists():
        return
    found = json.loads(path.read_text()).get("format")
    if found != FORMAT:
        raise incompatible(f"the run {Path(run_dir)}", found)
