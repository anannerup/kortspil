# 01: The bord owns its actions and its rules (rename and fold, no behaviour change)

**What to build:** A refactor that names the code after the domain, decided with Anders on 2026-10-25. Hjerterfri plays exactly as before; only where things live and what they are called changes. It prepares the code for es-makker (game no. 2).

- **`Table` (bord) is where everything happens.** Every action at a bord is a method on `Table`: sitting down, standing up, adding/removing a bot, changing settings, starting, and in a spil passing, playing a card, the moon choice, leaving, the next runde, play again, bot moves. `TableCommands` goes away.
- **The bord decides what is allowed, so refusals belong to `Table`.** Today a controller concern (`TableRefusals`) answers refusals; instead the bord's actions return their outcome (accepted, or refused with a reason) and the controllers only render it. The concern goes away.
- **The vært is the bord's owner** (glossary: Vært; `tables.host_id`). Only the vært changes settings, adds bots and starts.
- **`LiveGame` folds into `Game` (spil):** a spil can give its engine state itself. "Live" goes away.
- **Rules = TableRules + GameRules.** `RulesParams` is removed. *TableRules* are the bord's own rules (kind: open/password/private, and later e.g. the number of runder or the turn clock); *GameRules* are the card game's rules (hjerterfri: end score and house rules; es-makker later: påhæng tiers, jokers, bank …). Together they make up the bord's *Rules*.
- **The turn clock job:** `TableTickJob` is renamed after what it does (the tur-ur: warning and forladt), e.g. `TurnClockJob`, or folded into `TurnClock`. `TableScheduler` goes if the fold makes it unnecessary.
- **Frontend:** `PassFlights` becomes part of `CardAnimations` (it is one of several card animations: the pass, flights into the stik, the sweep). `SidePanel` stays.
- **Glossary:** add *tur-ur* (turn clock) and *bytning* (the pass); add *TableRules*/*GameRules* only if Anders wants them as domain words.

**Blocked by:** the `lobby-bord` branch (unstarted borde not in the DB, puf from the bord, settings on the right) being merged, as it changes the same files.

**Status:** done

- [x] All bord actions are methods on `Table`; `TableCommands` is gone.
- [x] Refusals come from `Table`; `TableRefusals` is gone; controllers only render outcomes.
- [x] `LiveGame` is folded into `Game`.
- [x] `RulesParams` is gone; `TableRules` and `GameRules` together form the bord's rules.
- [x] The turn clock job is named after the tur-ur.
- [x] `PassFlights` lives in `CardAnimations`.
- [x] GLOSSARY.md has tur-ur and bytning.
- [x] `bin/rails test`, `npm test`, `npx tsc --noEmit -p .` and rubocop are green; hjerterfri behaves exactly as before (same tests, renamed where needed).
