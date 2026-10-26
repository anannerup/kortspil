# 01: Den første es-makker-bot

**What to build:** Bots at an es-makker bord: empty seats can be filled with bots and an es-makker øvebord works. The bot melder 9 if legal, otherwise pas; never goes with on sol; never banks; every other choice (trump, called ace, kitty, discard, fordækt, card) is a random legal move. Acts through the bord's ordinary actions like hjerterfri's bots (Table::BotPlayer). See docs/bots/esmakker-strategy.md §2.

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] A whole spil can be played by one human and three bots, start to end.
- [ ] Bot level stored as for hjerterfri (seats.bot_level, history).
- [ ] Tests: bot only ever chooses legal moves; melder 9 then pas; never banks.
