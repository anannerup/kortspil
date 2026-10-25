# Botlab

The hjerterfri engine, the three bot levels (Let, Mellem, Svær) and the bot
measurements in Rust. Dev only: not built in Docker, not used in production.
Production runs the Ruby bot (`app/models/hjerterfri/bot.rb`,
`bot/knowledge.rb`), which must make exactly the same decisions.

Workflow: tune in Rust, port the change to Ruby, prove they agree with the
parity check.

    cd tools/botlab
    cargo build --release      # then ./target/release/botlab <command>

## Evaluation (spec §8)

Points per runde in a mixed tournament say as much about the opponents as
about the bot: a bot gets fewer points at a table with a weak bot. The main
measures therefore keep the cards and the opponents fixed and change only
the level being measured.

### Same hand, same seat (`hands`): duplicate play

    botlab hands --deals 50000 --seed 1 --fields mellem,svaer [--show 20]

Every deal is played once per level and per seat: Let, Mellem and Svær each
hold the very same hand from the very same seat, against the same field
(three bots of the field level), with the same pass direction and the same
variation seeds. Only the measured seat's level changes, so the difference
between two levels on a hand is their own doing, not the cards' or the
opponents'. Reported:

- points per runde per level, with a 95 % confidence interval;
- per pair (Svær–Mellem, Mellem–Let, Svær–Let): the share of hands where
  the stronger level did better, the same and worse with the same cards;
  how much it lost by when it did worse; and the mean difference with its
  95 % interval (paired per hand, so it is tight).

`--show K` lists the K hands where Svær did worst against Mellem;
`botlab trace --deal I --seat S --levels svaer,mellem` replays one of them
stik by stik for both levels.

### Spil against a fixed field (`eval`)

    botlab eval --spil 20000 --seed 1 --fields let,mellem,svaer

What decides a real game is who ends a spil lowest. One seat of level X
plays whole spil against three bots of a field level R; the same spil (same
seed, so the same deals runde by runde) is also played with R in X's seat.
X takes every seat in turn. Reported per field and level, with 95 %
intervals:

- **win %**: share of spil X ends lowest (ties split). With four equal bots
  this is 25 %, so the field's own level is the baseline;
- **vs field's seat**: X's win rate minus R's in the same seat on the same
  deals;
- **place**: average finishing place 1–4;
- **Δ point pr. runde**: X's points per runde minus R's in the same seat on
  the same deals;
- **rating**: Elo-style, from the win rate against three equal opponents
  (p = s / (s + 3), s = 10^(d/400)); 0 is the field's level.

### Tuning (`tune`) and finding losses (`regret`)

    botlab tune --levels svaer --fields mellem,svaer --deals 20000 --seed 1 \
      --try 'safe_shed=0.2,0.4;off=svaer:liability'

For each candidate (a number by name, or a rule switched off) the measured
level plays the same hands with the candidate and with the defaults,
against the default field; the difference (negative is better) is paired
per hand. Tune on seed 1 and confirm on seed 2 before keeping a change.
Every [valgt] number is a `Params` field and can be set on any command
(`--safe-shed 0.3`, `--moon-threat 17`, ...); `--off level:rule,...`
switches rules off (run `botlab` without arguments for the names).

    botlab regret --levels svaer --field mellem --deals 3000 --worlds 20

Analysis only, not a bot: at each Svær choice, every legal card is tried in
W worlds sampled from what Svær may know, played out by the bots, and the
choice's regret (its average points minus the best card's) is summed per
rule. The minimum over noisy averages biases regret upwards, so read it as
a ranking of rules worth rethinking and confirm any idea with `tune`.
`botlab voids` measures how often the giver of k cards of a suit is void in
it (the numbers behind `Knowledge::RECEIVED_VOID`).

### Side metric: the mixed tournament

    botlab tournament --spil 20000 --seed 1

Spil with the levels rotated over the seats (as the Ruby
`bin/rails 'bots:tournament[spil,seed]'`): points per runde and wins per
level. Kept for comparison with earlier runs only.

The Ruby side has the duplicate measure too, for the production bot:
`bin/rails 'bots:duplicate[400,1]'` (deals, seed, field; slow: about 4
deals a second).

## Parity

    bin/rails 'bots:parity[200,7]'    # [spil, seed]; from the repo root

Plays seeded spil with Ruby bots (random levels, J♦ and other house rules,
every pass direction, totals near the end score), writes every decision to
`tmp/bot_parity.jsonl` and runs `botlab parity` on it, which recomputes each
pass, play and moon choice and replays each whole runde with the Rust engine.
Any mismatch is printed with the view. Must report 0 mismatches.

Ruby semantics the port keeps: `Array#-` and `&` keep the receiver's order;
`min_by`/`max_by` take the first extreme in legal-move (display) order;
sorts carry a full tie-break (Ruby's `sort_by` is not stable); float sums
use Ruby's Kahan-Babuska `Array#sum`; float keys are computed in the same
order of operations.
