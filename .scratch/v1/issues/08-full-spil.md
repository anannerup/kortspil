# 08: A full spil

**What to build:** Runder continue until someone reaches the end score. A score sheet shows every runde and the running totals. The lowest total wins, and ties share the win. "Spil igen" starts a new spil at the same table.

**Blocked by:** 07 (Passing)

**Status:** done

Spec: `.scratch/v1/spec.md`

- [x] A game-level object adds up the runde results, applies the end score (100 for now) and determines the winner(s)
- [x] The score sheet shows one row per runde plus totals
- [x] The end screen shows the winner(s). Ties for lowest are shown as shared wins.
- [x] A finished spil is stored with status finished and its final scores
- [x] "Spil igen" creates a new game with the same seats
- [x] During a runde, each seat shows the points that seat has taken so far in this runde, which updates after every stik (taken stik are public information). When the runde ends, the final runde points per seat (incl. moon) are shown clearly.
- [x] A "Stilling" button on the table opens the score table at any time: one row per completed runde, one column per player, with totals at the bottom and the leader marked. It closes again without leaving the table.
- [x] "Forlad bordet" is visible on the table at all times. Leaving a spil in progress asks for confirmation in the page ("Forlad bordet? Du taber spillet."), stores the spil as abandoned with the scores so far and the leaver in `forfeited_by` (a loss), closes the practice table and returns to the lobby. Leaving a finished spil just closes the table.
- [x] Tests cover the end score, ties and runde numbering across a spil

## Comments

- Engine part done on branch eng-07-09: `Hjerterfri::Game` adds up runde results into score-sheet rows and totals, applies the end score, gives winner(s) with shared ties and the next runde number and pass direction; DB, score sheet UI and "Spil igen" still to do.

- 2026-10-20, Anders: you must be able to see the points you got in a runde, and to open stats for the spil, a table of who has how much. The two boxes above were added for this.

- Done on branch t07-08: after each runde the next is dealt automatically after a 10 s pause (`NextRundeJob`, or at once with "Næste runde"), with the next pass direction. The state message carries the score sheet from `Hjerterfri::Game` built from the stored rounds (rows, totals, leaders, winners) and the points each seat has taken so far (`Hjerterfri::Round#points_taken`, from completed stik). A finished spil stores `final_scores`; the practice table now stays open for "Spil igen". The "Forlad bordet" box was added at Anders's request (2026-10-20).

