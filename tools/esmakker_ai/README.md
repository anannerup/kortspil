# esmakker_ai

The es-makker engine in Python, for self-play training (ticket
`.scratch/esmakker-bots/issues/04-python-engine.md`, strategy
`docs/bots/esmakker-strategy.md` §3). Dev only: not built in Docker, not used
in production. The Ruby engine (`app/models/esmakker/`) is the authority; this
port is kept equal to it by a parity check on spil recorded from Ruby, like
`tools/botlab` does for hjerterfri.

The engine is Python ≥ 3.11 with the standard library only. The training
(ticket 05, section "Training" below) adds PyTorch and numpy
(`requirements-train.txt`).

## Setup (Windows)

From the repo root, in PowerShell:

    cd tools\esmakker_ai
    py -m venv .venv
    .venv\Scripts\Activate.ps1
    python -m unittest

(`.venv` is ignored by git. On macOS/Linux: `python3 -m venv .venv`,
`source .venv/bin/activate`.) Nothing needs installing for the engine. Every
command below runs from `tools/esmakker_ai`.

## Tests

    python -m unittest            # all, ~5 s
    python -m unittest tests.test_observation -v

- `test_parity`: replays `tests/fixtures/parity_sample.jsonl.gz` (200 spil,
  536 runder recorded from Ruby) and requires no difference;
  also checks the sample covers every melding on the ladder, both redeals,
  "det kan jeg selv", gå med, selvmakker, fordækt, 0/1/2 banks, vip card
  1/2/3, every trump and trumfløs, and sol with 1–3 players.
- `test_observation`: no hidden information leaks (below).
- `test_bots`: the first bot; FirstBot and Svær lay fordækt out of turn
  when self-play offers it.
- `test_svaer`: Svær's rules (the same cases as Ruby's `svaer_test.rb`), legal
  moves and no bank over many runder, and parity with the Ruby Svær on
  `tests/fixtures/svaer_parity_sample.jsonl.gz` (100 spil, ~5 900 decisions).
- `test_scoring`, `test_engine`: scoring examples from the Ruby tests,
  tokens, the ladder, legality, clone.
- `test_features`: the net's input shows a seat nothing it may not know
  (the same hidden-world swaps as `test_observation`, also at every step
  of choosing a discard and for the fordækt offer, and every card in it is
  one the observation names); every seat sees the exchange counts; the
  discard candidates are "stop" and the cards; the out-of-turn fordækt
  offer is "no fordækt" and the fordækt cards.
- `test_training` (skipped without PyTorch): a resumed run continues
  exactly, start/stop/resume, actor processes, legal play and no banks,
  the net exchanges 0–3 cards and lays fordækt out of turn, house rules
  only, an old run or checkpoint refuses to load with a clear message,
  the rating scale and `train rating`, a tiny run beats FirstBot.

## Parity with Ruby

The parity check needs Ruby only to record; the replay is pure Python, so
the committed fixture runs on Windows too.

Record and check thousands of spil in one go (on the Mac, from the repo root):

    bin/rails "esmakker:parity[3000,2026]"       # spil, seed
    PYTHON=python3.12 bin/rails "esmakker:parity[3000,2026]"

This writes `tmp/esmakker_parity.jsonl.gz` (`parity_record.rb`) and runs
`python -m esmakker_ai.parity` on it, which prints mismatches and a coverage
table. To check a recorded file anywhere:

    python -m esmakker_ai.parity path\to\esmakker_parity.jsonl.gz

To re-record the committed fixture after a Ruby rule change:

    bin/rails runner 'require Rails.root.join("tools/esmakker_ai/parity_record").to_s; EsmakkerParity.record("tools/esmakker_ai/tests/fixtures/parity_sample.jsonl.gz", spil: 200, seed: 1)'

What is recorded: seeded spil with random rules (påhæng order, joker and
bank toggles, bank window, point values with halves), the deal itself (so
Ruby's shuffle need not be reproduced), and random legal intents through
every part of a runde (jernhånd claims, all pass, every melding, "det kan
jeg selv", gå med, trump, aces, vip turning, the kitty, fordækt, banks, the
sol exchange). Before every action the check compares the phase, the seat
to act, every seat's legal actions, who each seat knows the esmakker to be,
and one seat's view (Ruby `Round#view_for` against `observe`: hand, card
counts, kitty, stik on the table, fordækt, open hand); after the runde the
log, the result and the points (exactly: Fractions against Ruby's
Rational); after the spil the totals.

## Layout

    esmakker_ai/
      cards.py        cards as ints 0–54 (suit*13+rank, jokers 52–54), hands as bitmasks
      meldinger.py    meldinger as ints 0–27, the ladder for a påhæng order
      actions.py      actions as ints (discards as card tuples), Ruby log tokens
      rules.py        Rules and Points (Esmakker::Rules/Points), amounts as Fractions
      engine.py       Round: bidding, play, sol play, result (mutable; clone() for search)
      scoring.py      Scoring (exact)
      observation.py  observe(round, seat): what that seat may know
      bots.py         FirstBot (strategy §2), RandomBot
      svaer.py        Svær (strategy §6), the training partner; SvaerParams
      svaer_parity.py checks Svær against the Ruby Svær (Esmakker::Svaer)
      svaer_bench.py  same hand, same seat: Svær against the first bot
      selfplay.py     play_runde, play_spil (deals, bank window, redeals)
      parity.py       replays Ruby recordings
      bench.py        speed
      features.py     the net's input as bits, straight from the engine (stdlib)
      net.py          the net (PyTorch)
      agent.py        NetPlayer, play(), training targets, explain() for "Vis kort"
      partners.py     the partner bots of training (FirstBot; the hook for Svær)
      actor.py        self-play runder -> samples; the actor processes
      learner.py      replay buffer, training step, checkpoints, the training loop
      evaluate.py     same-hand duplicate against FirstBot
      rating.py       the rating scale (0 = FirstBot, Svær ≈ +464)
      config.py       the settings
      train.py        the commands: start, stop, status, eval, snapshots
    parity_record.rb  the Ruby recorder (rake task esmakker:parity)
    requirements-train.txt
    svaer_parity_record.rb  the Ruby Svær recorder (rake task esmakker:svaer_parity)
    tests/

## Using the engine

    import random
    from esmakker_ai.engine import Round
    from esmakker_ai.observation import observe
    from esmakker_ai.bots import FirstBot
    from esmakker_ai.selfplay import play_runde, play_spil, random_deal

    r = Round(random_deal(random.Random(1)), dealer=0)   # standard rules
    seat = r.to_act()
    obs = observe(r, seat)
    r.apply(seat, obs["legal_actions"][0])

    rounds, totals = play_spil([FirstBot(s) for s in range(4)], runder=10, seed=1)

`play_runde` (and the training's `agent.play`) also offers a melder who is
not forhånd fordækt out of turn, once, before the forhånd leads the first
stik (`selfplay.fordaekt_offer`): the engine allows it then, but nobody
is "to act". A bot answers through `offer_fordaekt(obs)` (the
observation's legal actions are then the fordækt cards; None lays none):
Svær by the same rule as at its own lead (§6.4), FirstBot and RandomBot
half the time with a random card. A bot without the method never lays
fordækt out of turn.

- `Round.apply(seat, action)` changes the round in place (unlike Ruby's
  immutable Round) and raises `IllegalAction` on an illegal one;
  `check=False` skips the check for actions taken from `legal_actions`.
- `legal_actions(seat)` lists every action but a discard; when
  `discard_size(seat)` is N > 0 the seat lays away a tuple of N cards from
  `hand(seat)`.
- The bank window (vip) has nobody to act: the seats offered a bank may
  bank, and the window closes with "bankslut" by the melder (the bord's
  timer in the app). `selfplay.bank_window` asks the seats in turn.
- `points()` and `result()` give Fractions; `tokens()` the Ruby action log.

## The observation

`observe(round, seat)` is a dict with the seat's own hand, the public
bidding and actions, trump, the called ace, turned vip cards, the stik
played and who took them, and only what the seat has seen besides: the
kitty cards it took up (after its discard, never before; until the first
stik is taken), how many each seat exchanged, its own discards,
the fordækt card's face only for the melder, the bordlægger's open hand,
and the esmakker only once the seat knows her (as `Play#esmakker_known?`).
In the log, other seats' discards, a laid fordækt card and its play are
markers (`HIDDEN_DISCARD + n`, `HIDDEN_FORDAEKT`, `PLAY_FACE_DOWN`); in a
stik the fordækt card is `FACE_DOWN`.

Two tests prove nothing hidden leaks: every card an observation names is one
the seat has seen (worked out from the deal and the log, not from the
observation code), and hidden-world swaps: the cards the seat cannot see
are dealt differently (another seat holds the called ace, the kitty holds
other cards) and the same actions replayed; while they stay legal in both
worlds, the seat's observation is identical. A third swaps the kitty with
another seat's cards and checks that until the melder (the declarer at
halve) has laid away, nobody else whose hand is unchanged, herself
included, can tell (the kitty is unseen before the discard).

## Speed

`python -m esmakker_ai.bench 3000` on an Apple M5 Pro, Python 3.14:

| | runder/s | actions/s |
|---|---|---|
| raw engine, random legal actions | ~11 900 | ~750 000 |
| FirstBot / RandomBot on full observations | ~2 000–2 300 | ~125 000–137 000 |

The observation dict dominates; training should encode features straight
from the engine state (with the same visibility rules) or batch them.
Expect a few times slower on a typical Windows desktop CPU per core; run
several processes in parallel.

## Training

Self-play training as in strategy §3 (ticket 05), DouZero-style: the net
scores every legal action given what the seat may know, many runder are
played in parallel on the CPU, and the GPU learns from them.

- **Input** (`features.py`): about 1 200 bits encoded straight from the
  engine state with the visibility rules of `observation.py` (own hand,
  cards each seat played as seen, the stik on the table, shown renonces,
  the kitty only if the engine says the seat saw it, its own discards, how
  many cards each seat exchanged (public), who banked, the fordækt card's
  face only for the melder, the esmakker only once the seat knows her, the
  bidding, the bord's rules). Seats are relative to the seat. The encoder
  never reads the kitty itself, only `hand()` and `kitty_seen`, so the
  rule that the declarer lays away before taking up the kitty follows from
  the engine.
- **Exchanging** (REGLER §2.0: 0–3 cards, laid away before taking as many
  from the kitty): the net chooses one card at a time, with "lay away no
  more" (`DISCARD_STOP`) among the choices at every step, until it stops
  or has laid away as many as it may. So it chooses the count and the
  cards, at stik meldinger, at halve (the esmakker) and at each sol
  exchange. Stopping at once exchanges none.
- **Fordækt out of turn**: a melder who is not forhånd may lay fordækt
  until the forhånd leads. Nobody is "to act" for it, so the self-play
  driver (`agent.play`, like `selfplay.play_runde`) asks her once, right
  before the forhånd's lead: the net chooses between "no fordækt"
  (`NO_FORDAEKT`) and the fordækt cards; Svær and FirstBot partners answer
  through `offer_fordaekt` (above). A melder who is forhånd has fordækt
  among her actions at her own lead, as before.
- **House rules only**: training (and `eval`, `rating`) plays the
  standard bord of REGLER §2.0 (`rules.STANDARD`): "hvis man spiller med
  bots spiller man med husets regler" (Anders). There is no rules setting
  and nothing varies them; the rule bits of the input are kept (constant)
  so a later net can learn other bords without a new format.
- **Net** (`net.py`, 1.3 M weights, 5 MB): a state tower, an action
  embedding, and heads: Q per action (expected runde points if it plays
  that action), and from the state alone the expected runde points, its own
  stik, its makker's stik, and who holds the called ace (each other seat or
  the kitty) — what "Vis kort" will show (`agent.explain`).
- **Targets**: the runde's points for the seat (Monte Carlo, as DouZero),
  its stik and its makker's at the end, where the called ace was dealt. A
  redeal is 0 points.
- **Games**: one runde each. 25 % (`partner_share`) have Svær (strategy
  §6, `partners.py`) on the three other seats and the net in one seat; the
  rest are the net on all four. `--set partner=first` uses FirstBot
  instead.
- **Exploration**: 3 % random choices; 10 % in the meldingsrunde, then
  pas or one of the 3 lowest meldinger (without it everybody learns to pass
  early and there is little play to learn from; a random 13 vip only adds
  noise).
- **Never banks** (strategy §2): banking is not among the net's choices;
  the bank window closes with nobody banking.
- **Format**: `features.FORMAT` numbers the input and action layout (now
  2: the exchange count, the stop and no-fordækt actions). Checkpoints,
  snapshots and the run's `config.json` carry it; a run or weights file of
  another format refuses to resume or load and says so ("start a new run
  with --run NAME"), instead of crashing on the layer sizes. A run started
  before format 2 must be started anew, e.g. `start --run main2`.
- **Checkpoints**: every 10 minutes, and when stopped, the run saves the
  net, the optimizer, the replay buffer (bit-packed), every RNG and the
  counters to `checkpoint.pt`; `start` continues from it. Without actor
  processes (`actors=0`) a resumed run is bit-for-bit the run that never
  stopped (tested); with actors the order samples arrive in depends on
  timing, and resumed actors get new seeds.
- **Snapshots**: every 20 000 learner steps a numbered weights file
  `snapshots/step_000020000.pt` (~5 MB) and a quick duplicate eval against
  FirstBot in `snapshots/index.jsonl`, for picking Let and Mellem later.
  Each snapshot is then rated (below) in a background process at low
  priority (`rating_spil` = 400 spil, `rating_deals` = 200 deals; 0 turns
  it off), so the learner does not wait; its output goes to
  `rating.log`.

### Commands

All from `tools/esmakker_ai` with the venv active:

    python -m esmakker_ai.train start                 # start, or resume the run "main"
    python -m esmakker_ai.train start --set actors=6  # change a setting (kept in the run's config.json)
    python -m esmakker_ai.train stop                  # from another window: save and stop
    python -m esmakker_ai.train status
    python -m esmakker_ai.train snapshots
    python -m esmakker_ai.train eval --deals 2000 --workers 6
    python -m esmakker_ai.train eval --snapshot step_000100000.pt
    python -m esmakker_ai.train eval --reference pass   # PassBot in the seat instead of FirstBot
    python -m esmakker_ai.train eval --reference svaer --field svaer   # against Svær, at a Svær table
    python -m esmakker_ai.train rating                # rate the latest checkpoint
    python -m esmakker_ai.train rating --all --workers 6   # rate every snapshot not rated yet
    python -m esmakker_ai.train rating --snapshot step_000100000.pt
    python -m esmakker_ai.train rating --csv          # the table, and ratings.csv for a chart

Ctrl+C in the training window also saves and stops (wait for "saved ...").
`--run NAME` keeps several runs apart; `--max-minutes M` / `--max-steps N`
stop by themselves. A new run's settings can come from a JSON file
(`--config my.json`, keys as in `config.py`).

Runs live in `tools/esmakker_ai/runs/<run>/` (gitignored): `config.json`,
`checkpoint.pt` (resume point, ~65 MB with a full replay buffer),
`snapshots/`, `status.json`, `train.log.jsonl` (progress, losses,
checkpoints, snapshot evals), `ratings.jsonl` (and `ratings.csv`,
`rating.log`). Elsewhere: `--runs-dir D:\esmakker-runs`, or
set `ESMAKKER_RUNS`.

`status` shows the latest rating.

`eval` is same-hand duplicate play (as botlab `hands`): each deal is played
once per seat with the net there and once with the reference there
(`--reference first|pass|svaer`), the same cards and the same field
(`--field first|svaer`) with the same seeds. It reports points
per runde for both and the paired difference with 95 % intervals, how
often the net did better/same/worse with the same cards, and how often each
was melder and went home. FirstBot melder 9 whenever it may and loses,
so a net that only learned to pass already gains ~1.7 point/runde on it;
`--reference pass` (FirstBot that never melder) shows what it learned
beyond that. It also counts how often the net exchanged 0/1/2/3 cards.

### The rating: how much better is it?

One number on a fixed scale, Elo-style like botlab's `eval`:

- **0 = FirstBot.** The net sits in one seat against three FirstBots and
  plays whole spil of 10 runder; its win share p (share of spil it ends
  with the most points, ties split) gives the rating d by
  p = s / (s + 3), s = 10^(d/400): the rating difference to each of three
  equal opponents at which a four-player Elo model gives that win share.
  25 % is 0.
- **Svær ≈ +464** (wins 82.8 % of spil against three FirstBots;
  `train rating --svaer --spil 20000`, ±9). Svær is the scale's second
  anchor, measured once; re-measure if Svær or the rules change.
- **Reading it:** +100 means winning a spil against three FirstBots about
  as often as 3p/(1−p) = 10^(d/400) says: 0 → 25 %, +100 → 37 %,
  +200 → 51 %, +300 → 65 %, +464 (Svær) → 83 %, +600 → 91 %. Near Svær the
  scale is compressed (the win share approaches 100 %), so for a net
  around or above Svær read **Δ vs Svær** below rather than small rating
  differences.
- **Same-hand duplicate**: each spil is played twice from the same seed
  (the same deals, the same seeds for the three FirstBots), once with the
  net in the seat and once with FirstBot there; the win share is 25 % +
  the paired difference. Cards cancel out; FirstBot is exactly 0.
- **The interval** `[lo, hi]` is the 95 % confidence interval (the
  paired difference's, through the formula; it is not symmetric). Two
  ratings whose intervals overlap a lot are not shown to differ; with
  400 spil (the automatic rating) it is about ±40–60 at the low end,
  with 2 000 spil (`rating`'s default) about ±20.

Alongside, each rating records (in `ratings.jsonl`, one line per rated
file: step, time trained, runder, rating and interval, ...):

- **Δ vs Svær**: points per runde of the net minus Svær in the same seat
  at a Svær table (the human-like table), same-hand duplicate, ± 95 %.
  0 means as good as Svær with Svær partners; this is the number that
  matters for Umenneskelig.
- **Δ vs PassBot**: the same against PassBot at a FirstBot table: what
  it learned beyond not melding.
- **Melder**: how often the net is melder and goes home, against
  FirstBots and at the Svær table, and how many cards it exchanged.

`train rating` prints the run's table sorted by step, so the curve shows;
`--csv` writes `ratings.csv` (step, hours trained, rating, interval, Δs)
for a chart.

### Windows setup, step by step

1. **Python**: install Python 3.14 (64-bit) from python.org, ticking "Add
   python.exe to PATH" (or `winget install Python.Python.3.14`). Check in
   a new PowerShell: `py --version`.
2. **NVIDIA driver**: any recent Game Ready driver will do (CUDA 12.6
   needs 528 or newer). No CUDA toolkit to install: PyTorch brings its own.
3. **The venv** (PowerShell, from the repo root):

        cd tools\esmakker_ai
        py -3.14 -m venv .venv
        .venv\Scripts\Activate.ps1

   If PowerShell refuses to run the script:
   `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`, then again.
4. **PyTorch with CUDA**, from PyTorch's own index, then the rest:

        python -m pip install --upgrade pip
        pip install torch==2.14.1 --index-url https://download.pytorch.org/whl/cu126
        pip install -r requirements-train.txt

5. **Check the GPU**:

        python -c "import torch; print(torch.__version__, torch.cuda.is_available(), torch.cuda.get_device_name(0))"

   should print `2.14.1+cu126 True NVIDIA GeForce RTX 3070`. `False`
   means the CPU-only torch got installed: `pip uninstall torch`, then
   step 4 again.
6. **Tests**: `python -m unittest` (15–30 s; all OK).
7. **Start**: `python -m esmakker_ai.train start --set actors=6`. (A
   run "main" from before format 2 refuses to resume and says so: start
   anew with `--run main2`, or delete `runs\main`.) Actors
   are CPU processes playing runder; use the number of CPU cores minus 2
   (check with `python -c "import os; print(os.cpu_count())"`, which
   counts threads). The first lines say `device cuda`.
8. **Stop** before gaming: Ctrl+C in that window, or
   `python -m esmakker_ai.train stop` in another. It saves in a few
   seconds. **Resume**: the same `start` command (the run keeps
   `actors=6`).
9. Windows must not sleep while it trains: Settings → System → Power →
   Sleep "Never" while plugged in (or start it when you leave and stop it
   when you come back).

**Low priority.** Training lowers its own CPU priority to "below normal"
(`low_priority`, on by default), and the actor processes inherit it, so
Windows gives the CPU to anything else first. To be sure from the outside:
`start /belownormal python -m esmakker_ai.train start` in cmd. There is no
priority for the GPU: the learner uses it all the time, so stop training
before a game rather than playing alongside it. For light work alongside,
fewer actors help: `stop`, then `start --set actors=2`.

### Measured on the Mac

Apple M5 Pro (15 cores), MPS, 10 actors, default settings, 10 minutes:

| | |
|---|---|
| self-play | ~1 400–2 200 runder/s, ~33 000 samples/s (one actor: ~340 runder/s) |
| learner (MPS, batch 1024) | ~55–67 steps/s |
| 10 minutes | ~35 000 steps, ~850 000 runder |
| eval, 2 000 deals × 4 seats, 12 workers | ~5 s |

A short run learns not to melder (FirstBot's 9 on every hand loses), which
is worth ~+1.7 point/runde against FirstBot after the first minute. After
10 minutes (~31 000 steps, Svær partners) it was even with PassBot
(−0.03 ± 0.09), i.e. no better card play yet, and at a Svær table it lost
2.0 ± 0.2 point/runde to Svær in the same seat (it melder 15 % of runder
and goes home 34 %; Svær 12 % and 87 %). The real training is hours
on the RTX 3070; watch `snapshots` and `eval --reference pass`.

## Svær

`esmakker_ai.svaer.Svaer` is the rule bot of strategy §6, the same bot as
production's `Esmakker::Svaer`, decision for decision and thought for
thought. It acts on an observation like the other bots:

    from esmakker_ai.svaer import Svaer, SvaerParams
    bot = Svaer()                       # or Svaer(params=SvaerParams(makker_stik=...))
    action = bot.act(obs)               # None in the bank window: it never banks
    action, thought = bot.decide(obs)   # with the "Vis kort" thought

It is deterministic (the `seed` argument is ignored) and stateless, so one
instance can serve every seat. About 300 runder/s with Svær in all four
seats (Apple M5 Pro). The training's makker games (strategy §3) seat it
(`partners.py`).

Parity with Ruby (on the Mac, from the repo root):

    bin/rails "esmakker:svaer_parity[3000,2026]"

records seeded spil played by the Ruby Svær (half with Svær in all four
seats, half mixed with the first bot; random rules including Afkast) and
replays them here: at every step a Svær seat took, this Svær must make the
same move and think the same thought. To re-record the committed sample:

    bin/rails runner 'require Rails.root.join("tools/esmakker_ai/svaer_parity_record").to_s; SvaerParity.record("tools/esmakker_ai/tests/fixtures/svaer_parity_sample.jsonl.gz", spil: 100, seed: 1)'

Strength, same hand and same seat against a field of three:

    python -m esmakker_ai.svaer_bench 1000 1        # deals, seed[, field first|svaer]
