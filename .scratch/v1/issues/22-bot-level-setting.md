# 22: Choosing bot levels at the bord

**What to build:** The vært picks a level for each bot (Let, Mellem or Svær; Mellem by default) when adding it, and at a practice bord the human picks. The level is locked during a spil and can be changed between spil. Each seat shows "Bot · <niveau>". A bot that takes over the seat of a player who has forladt plays Let. That is provisional: Anders will revisit it.

**Blocked by:** 21 (Bot levels), 13 (Host controls)

**Status:** done

- [x] Each bot's level is stored on its seat. The default is Mellem. A takeover bot is Let.
- [x] Practice bord: the human can pick the level for each of the three bots before starting, and between spil.
- [x] Multiplayer bord: the vært picks the level when adding a bot. It can't be changed during a spil.
- [x] Seats show "Bot · Let/Mellem/Svær", and the takeover label is "Bot · Let (overtog fra Anders)".
- [x] Table-seam tests cover the default, the lock during a spil, changing between spil and the takeover level.

## Comments

**2026-10-26, agent:** Done on branch `bot-levels-ui`. Server: `WaitingTable#add_bot(level:)` (Mellem unless given) and `#change_bot_level` (vært only, at a practice bord too; `PATCH /borde/:id/bot` with `position` and `level`); the stored bord's `Table#change_bot_level` (TableChannel intent `change_bot_level`) lets the vært change it once the spil is finished and before "Spil igen", and refuses during a spil (`:spil_in_progress`). A takeover bot plays Let and keeps Let at the next waiting bord, where the vært may change it. The state carries each seat's `bot_level` and `host_seat`. UI: the seat list has a level picker per bot (and beside "+ Bot" on a free seat), the end screen has "Bots i næste spil" for the vært, and bots are named "Bot 2 · Svær" on the name tags, score sheet and lobby ("Bot · Svær" under the name in the setup seats), a takeover bot "Bot · Let (overtog fra Anders)". Tests: `test/models/bot_levels_test.rb`, request and channel tests. Open: the bots keep their numbers in labels ("Bot 2 · Svær" rather than a bare "Bot · Svær"), so three bots of one level stay distinguishable on the score sheet; Anders may want it otherwise.
