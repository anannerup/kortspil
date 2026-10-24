# 22: Choosing bot levels at the bord

**What to build:** The vært picks a level for each bot (Let, Mellem or Svær; Mellem by default) when adding it, and at a practice bord the human picks. The level is locked during a spil and can be changed between spil. Each seat shows "Bot · <niveau>". A bot that takes over the seat of a player who has forladt plays Let. That is provisional: Anders will revisit it.

**Blocked by:** 21 (Bot levels), 13 (Host controls)

**Status:** ready-for-agent

- [ ] Each bot's level is stored on its seat. The default is Mellem. A takeover bot is Let.
- [ ] Practice bord: the human can pick the level for each of the three bots before starting, and between spil.
- [ ] Multiplayer bord: the vært picks the level when adding a bot. It can't be changed during a spil.
- [ ] Seats show "Bot · Let/Mellem/Svær", and the takeover label is "Bot · Let (overtog fra Anders)".
- [ ] Table-seam tests cover the default, the lock during a spil, changing between spil and the takeover level.
