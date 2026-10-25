# 2. A bord lives in memory until its spil starts

**Status:** accepted (2026-10-25)

## Context

Anders: a bord that has not started "only lives in the lobby". Until now,
"Opret bord" wrote a `tables` row (status waiting) and its `seats` rows
straight away, and every sit, stand, bot and settings change was a
database write, for borde that were often never played. A bord being set
up must still be listed in the lobby, be opened by its link, take seats,
bots, settings and pufs (ticket 16) from several people, and show every
change live.

The app runs as one Puma process (no `WEB_CONCURRENCY`), with Action Cable
in that process (Solid Cable in production) and Solid Queue's supervisor
forked from Puma (`SOLID_QUEUE_IN_PUMA`), so jobs run in other processes.
The table chat already lives in this process's memory (`TableChat`), an
accepted v1 trade-off. Rails.cache is Solid Cache in production but a
memory store in development and a null store in tests, and has no atomic
read-modify-write.

## Decision

A bord before its spil is a `WaitingTable`: a plain Ruby value (seats,
bots, rules, type, password digest, the game chosen in the lobby, pufs),
kept in `WaitingTables`, a registry in the web process's memory, like
`TableChat`. Each change runs under one reentrant lock and broadcasts
inside it (lobby list, the bord's page, the nudged friends). Its URL is
`/borde/:id` with a random id that starts with a letter.

`TableCommands#start` creates the `tables` row, its four `seats` rows and
the `games` row (with runde 1) in one transaction, moves the chat over,
and drops the waiting bord, remembering which table it became so old
links lead to the spil. When a player stands up after a finished spil, the
stored bord closes and the others wait at a new `WaitingTable` with the
same seats, type and rules. Stored tables are never `waiting` any more; a
migration closed the ones that were.

Pufs live on the waiting bord too: they only exist before a spil, and end
with the start or the bord.

Nothing that runs in a job touches a waiting bord, so the forked Solid
Queue processes never need it. Pufs expire lazily against the injected
clock (on the next change, or when the bord's page asks at the expiry
time), not by a job.

## Consequences

- A restart or deploy drops every bord that has not started, with its
  pufs. Players see "Det bord findes ikke længere" and make a new one.
  Spil in progress are unaffected: they are stored.
- The app must stay one web process (as the table chat already requires).
  Running Puma with several workers would split the lobby.
  `bin/rails runner` and the console cannot see waiting borde.
- Solid Cache was the alternative that survives restarts, but it is not
  the cache store in development or tests, lacks atomic updates (seats
  would need a lock of their own), and its entries can be evicted.
- One bord per user checks both the registry and the stored seats
  (`User#current_table`).
- The admin page lists waiting borde from memory and stored ones from the
  database.
