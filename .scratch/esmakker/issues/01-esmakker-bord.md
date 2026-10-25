# 01: Es-makker bord: choose the game, set the bord, deal

**What to build:** The Es-makker box on the home page works and opens an es-makker bord (in the lobby until the spil starts, like hjerterfri). At the table the vært sets the bord's rules — number of runder (TableRules), and es-makker's GameRules with defaults from REGLER §2.0: påhæng order (vip > halve > gode, strict), joker beatable by trump (no), esmakker may bank first (yes), bank window (8 s), point values — and others see them read-only. "Start spil" works only with four humans (no es-makker bots in v1). The spil starts and deals 55 cards (52 + 3 jokers): 13 to each seat and 3 to the kitty; each player sees their own 13 cards (jokers with their own face) on an es-makker table in the same design as the hjerterfri table. Kortgiver and forhånd move clockwise each runde. The spil and stored bord record that they are es-makker. Nothing beyond the deal yet: the table says the meldingsrunde comes next.

**Blocked by:** None (table-refactor 01 and 02 are done).

**Status:** done

- [x] Es-makker box on the home page creates an es-makker bord; the game is fixed for the bord.
- [x] Es-makker settings at the table (TableRules: number of runder; GameRules with REGLER §2.0 defaults), read-only for non-vært.
- [x] Start only with four humans; bots can't be added at an es-makker bord.
- [x] `Esmakker` engine: 55-card deck with jokers, the deal with the kitty, dealer/forhånd rotation; per-seat view shows only the seat's own hand.
- [x] A runde is stored as its deal plus an (empty) action log and replays to the same state.
- [x] Engine and Table tests; the no-dead-ends test still passes.

## Comments

Built on branch `esmakker-01` (not merged). Decisions worth checking with Anders:
- Runde 1 is dealt by seat 0 (the vært), so seat 1 is forhånd; the kortgiver is stored per runde (`rounds.dealer`), so an all-pass redeal can move it later.
- Jokers are coded `X1`–`X3`.
- The number of runder is 1–50 (default 10); the bank window 5–10 s; point values any positive amount (halves allowed).
- Leaving an es-makker spil still behaves as at hjerterfri (a bot takes the seat); ticket 11 decides.
