# 08: A full spil

**What to build:** Runder continue until someone reaches the end score. A score sheet shows every runde and the running totals. The lowest total wins, and ties share the win. "Spil igen" starts a new spil at the same table.

**Blocked by:** 07 (Passing)

**Status:** in-progress

Spec: `.scratch/v1/spec.md`

- [ ] A game-level object adds up the runde results, applies the end score (100 for now) and determines the winner(s)
- [ ] The score sheet shows one row per runde plus totals
- [ ] The end screen shows the winner(s). Ties for lowest are shown as shared wins.
- [ ] A finished spil is stored with status finished and its final scores
- [ ] "Spil igen" creates a new game with the same seats
- [ ] During a runde, each seat shows the points that seat has taken so far in this runde, which updates after every stik (taken stik are public information). When the runde ends, the final runde points per seat (incl. moon) are shown clearly.
- [ ] A "Stilling" button on the table opens the score table at any time: one row per completed runde, one column per player, with totals at the bottom and the leader marked. It closes again without leaving the table.
- [ ] Tests cover the end score, ties and runde numbering across a spil

## Comments

- Engine part done on branch eng-07-09: `Hjerterfri::Game` adds up runde results into score-sheet rows and totals, applies the end score, gives winner(s) with shared ties and the next runde number and pass direction; DB, score sheet UI and "Spil igen" still to do.

- 2026-10-20, Anders: you must be able to see the points you got in a runde, and to open stats for the spil, a table of who has how much. The two boxes above were added for this.
