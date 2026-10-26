# 03: One way in for a player's action, and one module per game

**What to build:** Decided with Anders on 2026-10-26 (architecture review, candidates 1, 2 and 4). More games will come; the code must not ask "which game is this?" in more places. Which game a bord plays is **state set up once** — the bord and its spil know their game and hold that game's module — not a parameter passed around or a branch repeated in each method. No behaviour change.

1. **One way in for a player's action.** Today every action is written four times (the round's log codec, wire parsers in Table::Playing, BotPlayer turning intents back into strings, the TS ClientIntents) and passes two layers of one-line wrappers (TableChannel → Table::Playing). Keep what is truly shared in the bord: one "a player acts" entry point with the lock, save, scheduling, broadcast and refusal. Move what is the game's own — turning `{action, data}` into an engine intent — to one place per game, next to the existing log codec. A bot hands its engine intent straight to the shared entry point.
2. **One module per game behind Game/Round (the stored spil).** What is truly shared stays in Game: status, seats snapshot and seat log, version, turn clock, apply/save, the state envelope. What is the game's own moves into one object per game, chosen once from the spil's stored game: dealing a round row, rebuilding the engine round and game, the result each runde stores, steps per runde, which end of the totals wins, the game's state extras, the bot's turn, its rules (fold GameRules' mapping in). Remove the `esmakker?` branches (game.rb ×8, round.rb ×3, state.rb, bot_player.rb, Playing#play) and shims like `Esmakker::Round#passing? = false`.
   Do NOT merge the two engines (`Hjerterfri::Round`, `Esmakker::Round`) beyond the interface they already share; their phases and intents are only similar ("earn abstractions").
3. **The bank window's time belongs to es-makker.** Move the deadline logic (open, restart, close at expiry) into the es-makker module; the bord schedules a generic deadline of the spil without knowing what a bank is.

**Blocked by:** None.

**Status:** done

- [x] One player-action entry point at the bord; TableChannel and BotPlayer use it; the per-action one-liners are gone.
- [x] One decoder per game beside its log codec; the TS client intents stay as they are on the wire.
- [x] One module per game, chosen once from stored state; no `esmakker?`/game branches left outside the game modules (grep shows none).
- [x] Bank deadlines live in the es-makker module; the bord schedules a generic deadline.
- [x] Engines untouched beyond the shared interface; all tests green (hjerterfri and es-makker behave as before); channel tests per game instead of per action; adapters tested without ActiveRecord.

**Done (2026-10-26).**

- **One way in:** `Table#act(player:, intent:, surroundings:)` (Table::Playing) takes the engine intent of the bord's game and does the lock, save, deadline refusal, scheduling, broadcast and rejection. `TableChannel#perform_action` routes every action that is no channel method to it, decoded by `Table#client_intent` (the bord's card game). `BotPlayer` hands in `Game#bot_intent`. The 14 bord one-liners, the 16 channel one-liners and `BotPlayer#act_esmakker` are gone; WaitingTable's no-op list is `act`.
- **Decoders** beside the log codecs: `Hjerterfri::Round.client_intent`, `Esmakker::Round.client_intent` (+ `CLIENT_ACTIONS`). Wire and TS `ClientIntents` unchanged.
- **One module per card game:** `HjerterfriSpil`, `EsmakkerSpil` (plain Ruby, duck-typed, no base), registered once in `Game::CARD_GAMES` and chosen from the stored game (`Game#card_game`, `Table#card_game`, `Game.card_game(name)`). They answer: rules (GameRules reads through them), client intent, deal a runde row, round row errors, engine round/game, runde result, steps per runde, simultaneous (the bytte), redeal, best total, state extras, bot intent, whether the spil counts runder (replaces `TableRules::RUNDER_GAMES`), and the deadline.
- **Deadline:** `games.bank_closes_at` renamed `deadline_at`. `EsmakkerSpil.deadline / past_deadline / at_deadline` hold the bank window (open, restart on bank, close); `Game#apply(seat, intent, at:)` stores the deadline the card game sets; `Table#deadline_passed` + `DeadlineJob` + scheduler `deadline(...)` replace `close_bank_window` / `BankWindowJob`.
- **Removed:** `Game#esmakker?`, `Round#esmakker?`, `Round.deal!`, `Round#to_engine`, `Table#esmakker?`, `Esmakker::Round#passing?`, `Surroundings#strategy`, `GameRules::BY_GAME`, `Game::STEPS_PER_RUNDE`, `Game#banking? / track_bank_window! / bank_window_over?`.
- **Game names left in shared code, on purpose:** `Game::CARD_GAMES` (the one registry); the default game `"hjerterfri"` in keyword defaults (GameRules, Rules, TableRules, WaitingTable.build/set_up, WaitingTablesController); `Hjerterfri::Bot::LEVELS` in Seat/Seating (the levels are the only bot strategy's); `lib/tasks/bots.rake` (the hjerterfri bot tournament); comments.
