# 06: Practice table end-to-end

**What to build:** An approved user starts a practice table and plays one full runde against three bots in the browser. Moves go over Action Cable and the server enforces the rules. Cards use the card style from the Hjerterfri design system. The runde is stored, and it survives a page refresh and a server restart.

**Blocked by:** 03 (Signup, login and approval gate), 05 (Rules engine: one runde without passing)

**Status:** in-progress

Spec: `.scratch/v1/spec.md`

- [ ] The lobby has a "Øvebord" button that creates a table with the user plus 3 bots and starts immediately
- [ ] The table is driven through a table command interface (commands in, per-seat messages out). The Action Cable channel is a thin wrapper around it.
- [ ] Each seat has its own stream, so a client only ever receives its own hand
- [ ] Bots play a random legal card
- [ ] `games` and `rounds` are persisted, with one row per runde holding `deal` and `plays` strings. Each play is persisted before it is broadcast.
- [ ] After a refresh, or after the table is rebuilt from the DB, the player is back in their seat with the correct state
- [ ] `Card` and `CardBack` are ported to TypeScript from the design system (https://claude.ai/artifact/3jSKXTctgM3g9yLPKpyaWe), including the suit SVG paths, card tokens, sizes and Fraunces. The rest of the UI is plain and neutral.
- [ ] Legal cards are clickable and illegal ones are not
- [ ] When the runde ends, its points are shown
- [ ] Tests at the table seam cover a full runde with bots and a rebuild from the DB. There is one channel smoke test.
