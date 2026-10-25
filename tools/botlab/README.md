# Botlab

The hjerterfri engine, the three bot levels (Let, Mellem, Svær) and the bot
tournament in Rust. Dev only: not built in Docker, not used in production.
Production runs the Ruby bot (`app/models/hjerterfri/bot.rb`,
`bot/knowledge.rb`), which must make exactly the same decisions.

Workflow: tune in Rust, port the change to Ruby, prove they agree with the
parity check.

## Tournament

    cd tools/botlab
    cargo run --release -- tournament --spil 5000 --seed 1 [--threads N]

Prints points per runde and wins per level (lower is better; the aim is
Svær < Mellem < Let), plus Svær − Mellem and Mellem − Let with one standard
error. Override [valgt] numbers with `--risky 2.0 --safe 0.1
--moon-threat 14 --late 4 --high 8 --void-plan-hand 10 --safe-high-hand 11
--discard-evidence 0.2 --spade-evidence 0.4`; switch rules off per level for ablation with
`--off svaer:late,svaer:moon` (run without arguments for the rule names).
The defaults are Ruby's values.

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
use Ruby's Kahan-Babuska `Array#sum`.
