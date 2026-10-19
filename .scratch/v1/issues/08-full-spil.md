# 08: A full spil

**What to build:** Runder continue until someone reaches the end score. A score sheet shows every runde and the running totals. The lowest total wins, and ties share the win. "Spil igen" starts a new spil at the same table.

**Blocked by:** 07 (Passing)

**Status:** ready-for-agent

Spec: `.scratch/v1/spec.md`

- [ ] A game-level object adds up the runde results, applies the end score (100 for now) and determines the winner(s)
- [ ] The score sheet shows one row per runde plus totals
- [ ] The end screen shows the winner(s). Ties for lowest are shown as shared wins.
- [ ] A finished spil is stored with status finished and its final scores
- [ ] "Spil igen" creates a new game with the same seats
- [ ] Tests cover the end score, ties and runde numbering across a spil
