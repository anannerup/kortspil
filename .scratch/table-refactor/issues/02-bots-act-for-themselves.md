# 02: A bot is a player that acts for itself

**What to build:** Decided with Anders on 2026-10-25, closer to the domain (glossary: *Bot* — "a computer player in a seat"). Today the bord plays the bots' moves (`Table#bot_turn`). Instead, a bot is a player in a seat that acts for itself: when it is its turn, it reads what its seat may see, chooses with its strategy (Let, Mellem or Svær) and performs the action through the bord's ordinary actions — the same ones a human uses (pass, play, the moon choice). The bord only judges and carries out actions and doesn't know whether a human or a bot made them.

- **Takeover:** when a player forlader, the bord puts a bot in the seat (Let for now, ticket 22), and from the next move that bot plays on as the seat's player. Taking over is simply the seat getting a new player.
- **Strategy vs player:** `Hjerterfri::Bot` (the strategy, tuned in tools/botlab and kept in parity) stays as the bot's brain, unchanged. The new bot player uses it; one player concept per seat occupant (human or bot).
- **Level on the seat:** the bot's level is stored with the bot in its seat (default Mellem; takeover Let), ready for ticket 22's level choice.
- **Scheduling:** the job that wakes a bot asks that bot to take its turn (rename the job after that, e.g. "a bot's turn"); the stale/duplicate guard (version check) stays.
- No behaviour change for hjerterfri besides the level now being per seat (all bots still play Mellem unless a takeover).

**Blocked by:** table-refactor 01 (done); the J♦ −10 bot change on main (finish first, it touches the bot code).

**Status:** done

- [x] Bots act through the bord's ordinary actions; `Table#bot_turn` is gone.
- [x] A takeover bot is a new player in the seat and plays on from the next move.
- [x] The bot's level is stored per seat (default Mellem, takeover Let) without a visible UI yet.
- [x] The strategy (`Hjerterfri::Bot`) and parity are unchanged.
- [x] All tests green; hjerterfri plays as before.

## Comments

**2026-10-25, agent:** Done on branch `bot-players`. `Table::BotPlayer` (seat, level) is the bot in a seat: `BotPlayer.wake` (run by `BotTurnJob`) finds the bot in the seat and asks it to `take_turn`; it checks the turn is still due (`Game#bot_turn_due?`), reads its seat's view, chooses with `Hjerterfri::Bot` at its level (`Surroundings#strategy`) and calls `Table#pass` / `#play` / `#choose_moon` with `player: self`, the same actions a human calls with `player: user`. `Table#bot_turn` is gone. `seats.bot_level` (check: set exactly when `bot_name` is) holds the level: Mellem when seated, Let on takeover (`Seating::BOT_LEVEL`, `TAKEOVER_LEVEL`); it is on the waiting bord's occupants and in the lobby JSON (`bot_level`), with no UI. The spil's start snapshot (`games.seats`) and `seat_log` do not record the level.
