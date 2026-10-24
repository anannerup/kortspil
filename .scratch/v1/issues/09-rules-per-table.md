# 09: Rules configuration per table

**What to build:** The host picks the rules when creating a table, starting from the "Standard hjerterfri" preset: end score, "spar dame bryder hjerter", "ruder knægt giver minus 10" and shooter's choice. The rules are shown before sitting down and locked once the first runde is dealt.

**Blocked by:** 08 (A full spil)

**Status:** in-progress

Spec: `.scratch/v1/spec.md`

- [x] The rules config lives on the table and is snapshotted onto each game
- [x] The end score can be configured
- [x] With Q♠-breaks-hearts on, playing Q♠ breaks hearts
- [x] With J♦ −10 on, whoever takes J♦ gets −10 for that runde. The moon is judged on the 26 penalty points. J♦ never applies to the moon shooter; another seat that took J♦ still gets −10.
- [x] With shooter's choice on, the moon shooter chooses after the 13th stik: 26 to everyone else, or −26 to themselves. Off, everyone else gets 26.
- [x] The score sheet shows J♦ when the toggle is on
- [x] The rules can't be changed after the first deal
- [x] Engine tests cover each toggle on and off
- [ ] The rules are shown before sitting down: comes with the lobby (12). Practice tables have no sitting down; the rules show on the score sheet ("Stilling").
- [x] Answered by Anders (2026-10-25): J♦ −10 is a per-table setting, off by default (J♦ is an ordinary card). J♦ does not apply to a moon shooter. Shooter's choice is a per-table setting, off by default.

## Comments

- 2026-10-25: Table config, lock, shooter's choice and UI done. `tables.rules` holds the host's choice and each game snapshots it. `Table` refuses a rules change once it has a spil. The practice table form in the lobby sends the rules. Under shooter's choice the runde has a `choosing_moon` phase (`Hjerterfri::MoonChoice`, stored in `rounds.moon_choice`). A bot shooter uses a provisional rule (ticket 20). Remaining: show the rules before sitting down, once the lobby lists tables (12).

- Engine part done on branch eng-07-09: `Rules` has `queen_breaks_hearts` and `jack_of_diamonds_minus_ten` (both off in `Rules.standard`) and round-trips through a plain hash (`to_h` / `from_h`); moon judged on the 26 penalty points with J♦ −10 on top, also for the shooter (inferred, open question above still stands). Table config, lock and UI still to do.
