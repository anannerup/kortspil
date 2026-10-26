# esmakker_ai

The es-makker engine in Python, for self-play training (ticket
`.scratch/esmakker-bots/issues/04-python-engine.md`, strategy
`docs/bots/esmakker-strategy.md` §3). Dev only: not built in Docker, not used
in production. The Ruby engine (`app/models/esmakker/`) is the authority; this
port is kept equal to it by a parity check on spil recorded from Ruby, like
`tools/botlab` does for hjerterfri.

The engine is Python ≥ 3.11 with the standard library only. PyTorch comes in
with the training, not here.

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
  559 runder, ~30 000 steps recorded from Ruby) and requires no difference;
  also checks the sample covers every melding on the ladder, both redeals,
  "det kan jeg selv", gå med, selvmakker, fordækt, 0/1/2 banks, vip card
  1/2/3, every trump and trumfløs, and sol with 1–3 players.
- `test_observation`: no hidden information leaks (below).
- `test_bots`: the first bot.
- `test_svaer`: Svær's rules (the same cases as Ruby's `svaer_test.rb`), legal
  moves and no bank over many runder, and parity with the Ruby Svær on
  `tests/fixtures/svaer_parity_sample.jsonl.gz` (100 spil, ~5 900 decisions).
- `test_scoring`, `test_engine`: scoring examples from the Ruby tests,
  tokens, the ladder, legality, clone.

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
    parity_record.rb  the Ruby recorder (rake task esmakker:parity)
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
kitty if it took it up (or saw it at the sol exchange), its own discards,
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
worlds, the seat's observation is identical.

It differs from Ruby's view in one place on purpose: during the sol
exchange `kitty_count` is what is left of the kitty (Ruby shows 0).

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
seats (Apple M5 Pro). For the training's makker games (strategy §3), put
`Svaer()` in the seats that are not the net's.

Parity with Ruby (on the Mac, from the repo root):

    bin/rails "esmakker:svaer_parity[3000,2026]"

records seeded spil played by the Ruby Svær (half with Svær in all four
seats, half mixed with the first bot; random rules including Afkast) and
replays them here: at every step a Svær seat took, this Svær must make the
same move and think the same thought. To re-record the committed sample:

    bin/rails runner 'require Rails.root.join("tools/esmakker_ai/svaer_parity_record").to_s; SvaerParity.record("tools/esmakker_ai/tests/fixtures/svaer_parity_sample.jsonl.gz", spil: 100, seed: 1)'

Strength, same hand and same seat against a field of three:

    python -m esmakker_ai.svaer_bench 1000 1        # deals, seed[, field first|svaer]
