# 05: Points and the score sheet

**What to build:** Every runde is scored by REGLER §2.0 "Point": a melding that goes home wins (stake + overstik) × doublings, bet loses stake × missing stik × doublings; stakes 8 = 1 … 13 = 3.5; påhæng ×2; trumfløs ×2; each loser pays each winner (two against two), selvmakker against all three. Points are a zero-sum running score from 0. After each runde players see who won what; a score sheet shows every runde and the running totals, with the lookup table (melding × overstik) as the family uses it. The point values are a bord setting with the family table as default. Vip's card factor and banks are added in 07/08; sol values in 09.

**Blocked by:** 03

**Status:** ready-for-agent

- [ ] Engine scoring matches every cell of REGLER's lookup table, bet, påhæng and trumfløs doublings, selvmakker.
- [ ] Zero sum after every runde; running totals and final standing.
- [ ] Score sheet and runde result in the UI; point values editable by the vært before the start.
- [ ] Stored runde results replay to the same totals.
