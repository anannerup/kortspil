# 06: Practice table end-to-end

**What to build:** An approved user starts a practice table and plays one full runde against three bots in the browser. Moves go over Action Cable and the server enforces the rules. Cards use the card style from the Hjerterfri design system. The runde is stored, and it survives a page refresh and a server restart.

**Blocked by:** 03 (Signup, login and approval gate), 05 (Rules engine: one runde without passing)

**Status:** done

Spec: `.scratch/v1/spec.md`

- [x] The lobby has a "Øvebord" button that creates a table with the user plus 3 bots and starts immediately
- [x] The table is driven through a table command interface (commands in, per-seat messages out). The Action Cable channel is a thin wrapper around it.
- [x] Each seat has its own stream, so a client only ever receives its own hand
- [x] Bots play a random legal card (in practice the provisional `Hjerterfri::Bot` strategy from ticket 10, which only ever picks from the legal moves)
- [x] `games` and `rounds` are persisted, with one row per runde holding `deal` and `plays` strings. Each play is persisted before it is broadcast.
- [x] After a refresh, or after the table is rebuilt from the DB, the player is back in their seat with the correct state
- [x] `Card` and `CardBack` are ported to TypeScript from the design system (https://claude.ai/artifact/3jSKXTctgM3g9yLPKpyaWe), including the suit SVG paths, card tokens, sizes and Fraunces. The rest of the UI is plain and neutral.
- [x] Legal cards are clickable and illegal ones are not
- [x] When the runde ends, its points are shown
- [x] Tests at the table seam cover a full runde with bots and a rebuild from the DB. There is one channel smoke test.
