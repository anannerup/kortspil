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
    actor_games: int = 1              # spil each actor plays at once, their decisions scored in one batch
    actor_inference: str = "local"    # "local": each actor holds the net; "server": the actors import no torch
                                      # and one inference process on actor_device scores for all (inference.py)
    actor_groups: int = 1             # with "server": game groups per actor, each actor_games spil in its own
                                      # thread, one playing while another waits for the server (actor.actor_main)
    inference_fp16: bool = False      # with "server" on CUDA: the server's net (scoring and GPU rollouts) in half
                                      # precision, the RTX's tensor cores; Q equal up to fp16 rounding (learner fp32)
    bid_by_partner: float = 0.0       # share of net-only runder where the partner bot bids for all seats
    no_sol: bool = False              # the net never melder a sol-melding nor goes along on one (a stik net, Anders)
    # the net
    hidden: int = 512
    action_hidden: int = 128
    points_scale: float = 10.0        # the Q and value heads learn points / points_scale
    contract: bool = False            # the contract head: the side's stik per trump if this seat becomes melder (net.py)
    contract_weight: float = 0.5      # ... its loss weight
    contract_mix: float = 0.0         # ... the share of a stik bid's Q replaced by the melding's value priced from it
    contract_search: bool = True      # ... a searched trump choice also gives it the side's stik of every rollout
    contract_cf: bool = False         # ... counterfactual labels: at each seat's first bid of a net-only runde, what
                                      # its side takes if it became melder with each trump (search.py)
    contract_cf_share: float = 1.0    # ... the share of those first bids that get them
    contract_cf_worlds: int = 1       # ... worlds per trump (one row each: an unbiased draw of the side's stik)
    # meldinger and the declaration by simulation (search.py; Anders, 27 Oct: "måske skal nettet slet ikke
    # melde selv, måske skal det altid simulere 100 spil og så bruge det som afsæt")
    bid_by_simulation: bool = False   # every bid of the net is searched: pas and the stik meldinger of the next
                                      # bid_sim_numbers numbers, each in bid_sim_worlds worlds, the rest of the
                                      # meldingsrunde bid by the net's contract guess (contract_mix 1); best mean wins
    bid_sim_share: float = 1.0        # ... in this share of runder (drawn per runde); the rest bid by the guess
    bid_sim_worlds: int = 16         # ... worlds per option in training (SimulatingPlayer takes its own, e.g. 100)
    bid_sim_numbers: int = 2          # ... how many melding numbers up from the lowest legal one are options
    declare_by_simulation: bool = False  # the melder's trump, called ace, fordækt card always searched the same way
    declare_sim_max: int = 8          # ... all candidates up to this many, else the net's Gumbel top search_gumbel_k_play
    contract_bias_target: float = -0.3  # the contract guess under the rollouts' side stik by more than this (stik,
                                      # a moving mean): contract_weight is raised stepwise (Anders: the net will be
                                      # too defensive); back down once within contract_bias_ok
    contract_bias_ok: float = 0.1
    contract_bias_max: float = 3.0    # ... at most this many times contract_weight
    contract_bias_every: int = 0      # ... learner steps between adjustments (0: never; the new run: 200)
    melder_check_share: float = 0.0   # share of net-only runder where every seat is also played as melder on the
                                      # real deal: how often the contract guess picked the strongest melder
    # self-play
    epsilon: float = 0.03             # share of random choices while playing
    bid_epsilon: float = 0.1          # ... in the meldingsrunde: pas or one of the 3 lowest meldinger
    partner_share: float = 0.25       # share of games with the partner bot on the three other seats
    partner: str = "svaer"            # partners.py: "svaer" (strategy §6) or "first"
    # the spil: a self-play game is a whole spil of `runder` runder, the points adding up (spil.py)
    runder: int = 10                  # runder in a spil (the house standard; a redeal does not count)
    spil_weight: float = 0.5          # Q = runde points + spil_weight × Δ(expected margin + win_value × win share)
    win_value: float = 20.0           # what winning the spil is worth on top of the margin, in points
    spil_target: str = "expected"     # "expected": the runde's change in the expected outcome (low noise);
                                      # "outcome": the spil's actual end less the expected outcome before the runde
    runde_sd: float = 4.7             # spread of a seat's points per runde in the "expected" model (Svær table)
    # search (search.py): rollout Q targets for the top candidates at a share of the net's decisions
    search_share: float = 0.0         # share of the net's play decisions searched (0: off)
    search_share_bid: float = 0.0     # ... of its meldingsrunde, declaration and fordækt-out-of-turn decisions
    search_k: int = 3                 # the net's top candidates by Q that are searched ...
    search_random: int = 1            # ... plus this many other candidates at random
    search_bid_lowest: int = 0        # in the meldingsrunde also pas and the lowest this many legal stik meldinger, always
    search_bid_up_to: int = 0         # ... and the plain stik melding of every number up to this one
    search_bid_sol: float = 0.2       # ... and the sol-meldinger at this share of the searched bids
    search_gumbel_k: int = 0          # >0: in the meldingsrunde search this many drawn from all legal actions,
    search_gumbel_tau: float = 2.0    # ... with chance softmax(Q / tau), tau in points (Gumbel AlphaZero)
    search_gumbel_k_play: int = 0     # >0: the same at every other searched decision (cards, trump, ace, ...)
    search_bid_pas: bool = False      # a searched bid always tries pas too: what letting the others have it costs
    search_worlds: int = 8            # worlds sampled from what the seat may know; every candidate plays in each
    search_weight: float = 1.0        # the loss weight of a searched (state, action, rollout mean) row
    search_play_z: float = 2.0        # the actor plays the search's best only when it beats the net's choice by z SE
    search_explore: float = 0.05      # share of searched decisions that play a random searched candidate
    search_belief: int = 0            # >1: draw this many worlds per kept one, keep them by how well they explain the bids
    search_belief_miss: float = 0.05  # ... a bid the world's player would not have made multiplies the weight by this
    search_gpu_rollouts: bool = False  # play the rollouts' card play (stik, the net at every seat) on the GPU (trollout)
    search_gpu_batch: int = 1024      # ... once this many wait (or nothing else is left to play): a big batch is cheaper
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
    win_weight: float = 0.5           # ... of the spil-win head
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
    # the league and the ladder (Anders: self-play only, and better than its own earlier versions)
    league_share: float = 0.0         # share of self-play spil where 1-3 seats are an earlier snapshot of the run
                                      # (no samples from those seats; actor_inference "server" only)
    league_models: int = 4            # ... earlier snapshots the inference server holds, drawn anew per new snapshot
    ladder_deals: int = 0             # each snapshot vs the one ladder_gap snapshots before it, duplicate deals
                                      # (x 2 fields; 1 000 = 2 000 paired runder; 0: off), in the background
    ladder_gap: int = 3               # ... 3 snapshots = 60 000 steps at snapshot_steps 20 000
    ladder_deals_all: int = 250       # ... and vs every other earlier snapshot (at most ladder_all_most), cheaper
    ladder_all_most: int = 8
    ladder_workers: int = 2           # processes for the ladder, at low priority
    low_priority: bool = True         # lower the process priority (CPU only; see README)
    min_free_memory_gb: float = 3.0   # save and stop when the machine's free RAM or commit falls below this

    @classmethod
    def from_dict(cls, values):
        values = {k: v for k, v in values.items() if k != "format"}
        if values.get("rules") is not None:
            raise ValueError("training plays only the house rules; the setting 'rules' is gone")
        values.pop("rules", None)
        if values.get("spil_target", "expected") not in ("expected", "outcome"):
            raise ValueError("spil_target is 'expected' or 'outcome'")
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
        f"(format 3: the net sees the spil, its runde and the standing, and plays to win the spil). "
        f"It cannot be resumed or loaded: start a new run with --run NAME (e.g. --run main{FORMAT}), "
        f"from format 2 with --init FILE to start from its net, or check out the older code to use it.")


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
