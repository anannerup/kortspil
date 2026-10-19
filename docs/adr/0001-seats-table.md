# 1. Seats are rows of their own, not part of the spil

**Status:** accepted (2026-10-20)

## Context

Who sits where lived only in `games.seats`, a JSON column documented as
"the players at the start" but read as the current occupants. Seats did not
exist until a spil started, so sitting and standing before the start
(ticket 12) had nowhere to live, and a bot taking over a seat (ticket 19)
would have had to rewrite the start snapshot. "Which bord does this user
sit at" scanned every open bord in Ruby, and the one-bord-per-user rule
(ticket 12) needs that question answered cheaply.

## Decision

A `seats` table: one row per seat of a bord (`table_id`, `position` 0-3,
nullable `user_id`, nullable `bot_name`, timestamps), unique on
`[table_id, position]`, indexed on `user_id`, with check constraints for the
position range and for at most one occupant. It holds who sits there *now*,
before and during a spil. All reads and changes go through
`Table::Seating`.

`games.seats` stays as the immutable snapshot taken when a spil starts, and
`games.seat_log` records each later change (`{seat, from, to, at_play}`,
`at_play` being the spil's version at the takeover), so a replay can tell
who held a seat at every step.

A data migration backfilled the seats of existing borde from their latest
spil's snapshot plus its seat_log. Closed borde keep their seat rows, so a
returning player is still recognised and sent back to the lobby.

## Consequences

- `User#current_table` is one indexed query.
- Seats exist before a spil, so ticket 12 (sit/stand, one bord per user),
  13 (vært handover, add/remove bots) and 16 (puf cap: pending + seated +
  bots ≤ 4) extend `Table::Seating` instead of the spil.
- One-bord-per-user is not a database constraint: closed borde keep their
  rows, so it is checked against borde that are not closed.
- Two sources must agree at the start of a spil: the snapshot is copied
  from the seat rows (`Seating#snapshot`) and never written otherwise.
