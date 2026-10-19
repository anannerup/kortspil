# 09: Rules configuration per table

**What to build:** The host picks the rules when creating a table, starting from the "Standard hjerterfri" preset: end score, "spar dame bryder hjerter" and "ruder knægt giver minus 10". The rules are shown before sitting down and locked once the first runde is dealt.

**Blocked by:** 08 (A full spil)

**Status:** ready-for-agent

Spec: `.scratch/v1/spec.md`

- [ ] The rules config lives on the table and is snapshotted onto each game
- [ ] The end score can be configured
- [ ] With Q♠-breaks-hearts on, playing Q♠ breaks hearts
- [ ] With J♦ −10 on, whoever takes J♦ gets −10 for that runde. Shooting the moon is still judged on the 26 penalty points, and J♦ applies on top (inferred, not sourced; see open question).
- [ ] The score sheet shows J♦ when the toggle is on
- [ ] The rules can't be changed after the first deal
- [ ] Engine tests cover each toggle on and off
- [ ] Open question for Anders: should J♦ −10 be on by default in the preset? Should J♦ apply to a moon shooter?

## Comments

- Engine part done on branch eng-07-09: `Rules` has `queen_breaks_hearts` and `jack_of_diamonds_minus_ten` (both off in `Rules.standard`) and round-trips through a plain hash (`to_h` / `from_h`); moon judged on the 26 penalty points with J♦ −10 on top, also for the shooter (inferred, open question above still stands). Table config, lock and UI still to do.
