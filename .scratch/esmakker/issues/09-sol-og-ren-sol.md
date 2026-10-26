# 09: Sol and ren sol

**What to build:** Sol and ren sol join the ladder at their places (after 9 with påhæng and after 10 with påhæng). Players who haven't passed can "gå med" and play the same melding themselves; "det kan jeg selv" works on them too. The kitty goes to the melder first, then those who went with, then clockwise from the melder. The forhånd leads. The ace is the lowest card and there is no trump. Sol: may take one stik; ren sol: no stik. The runde is played to the end even when a sol player is væltet, and stops when all sol players are væltet. Each sol player is settled separately against the others with a fixed value (sol 3, ren sol 4 — inferred defaults, bord setting).

**Blocked by:** 02, 05

**Status:** done

- [x] Ladder, gå med, "det kan jeg selv" on sol.
- [x] Kitty order; forhånd leads; ace lowest, no trump.
- [x] Væltet / played to the end / early stop when all væltet.
- [x] Fixed points per sol player.
- [x] Engine and Table tests; UI for gå med.

## Comments

### Built (branch `esmakker-09`)

- `Esmakker::SolPlay` (new, next to `Play`) plays sol and ren sol after the meldingsrunde: `:exchanging` → `:playing` → `:complete`. `Round#start_play` picks it for a sol-melding (with the bidding's `went_with`, in order). No new intents or bord actions: the exchange is `Discard` (log token `kast-…`, `Table#discard`, the `discard` channel action), the stik `PlayCard`; the runde replays from the log. ChooseTrump/CallAce/vip/fordækt intents are refused `not_now`.
- `Esmakker::SolResult` (kind `:sol`) carries players, most stik, væltet, stik per seat and points; `Scoring.sol_points` settles it. Bordlægger/ren bordlægger stay "ikke spillet": ticket 10 adds them to `SolPlay::PLAYED` (the stik limit is already in `MOST_STIK`) plus the open hand in `view_for`.
- Views: `play.kind: "sol"`, `players`, `most_stik`, `vaeltet`, `exchange_order`, `exchanging`, `discard_size`; the stik melding's fields are sent empty so the client reads both alike. Only the seat exchanging sees the kitty; each seat only its own cards laid away. Hands are sorted with the ace lowest once a sol-melding is won.
- UI (`sol.ts`, node-tested; hooks in `play.ts`, `timeline.ts`, the table page): the centre says who plays sol and whose turn at the kitty, with "Læg N kort væk" and "Behold mine kort"; name tags "melder" / "går med" / "· væltet"; the frame's corner lists each sol player's stik ("Højst ét stik"), væltet in red; the result card and score sheet per sol player (klaret / væltet, stopped early). Screenshots: exchange, play and result, 1400×900 and 400 px.
- Tests: `test/models/esmakker/sol_play_test.rb` (kitty order and partial exchanges, nobody exchanges, forhånd leads, ace lowest in play and hand order, jokers, væltet, played to the end, early stop, ren sol, random runder zero-sum + replay), `sol_scoring_test.rb` (alone, several sol players, all four, bord amounts), `test/models/esmakker_sol_table_test.rb` (a whole sol runde through the bord), `app/frontend/esmakker/sol.test.ts`. The three "ikke spillet" tests now use bordlægger.

### Valg — for Anders to confirm

- **S1. What "bytter" means at sol.** Each seat in turn takes up what is left of the kitty and lays as many cards away, any of them: her own cards laid away leave the runde unseen; kitty cards she lays back go on to the next seat. So the melder may take all three, some, or none ("Behold mine kort"). From REGLER §2.5 ("Bytter spilføreren ikke alle tre, får spilleren efter … lov at bytte de resterende") with §2.0's order. The next seat thus learns which kitty cards the earlier ones did not want.
- **S2. Order:** the melder, then those who went with **in the order they went with**, then the rest clockwise from the melder (the modspillere get a turn too, §2.0 "videre med uret"). §2.5/§2.10's Whistklubben rule (the last to go with first) is not used. The exchange ends when the kitty is empty or all four have had a turn; what is left is out of the runde, unseen. **Confirmed 2026-10-26 (Anders).** Melder → those who went with → the rest; in practice nothing is left.
- **S3. Who sees what:** others see only how many cards the seat exchanging holds (13 + n) and whose turn it is.
- **S4. The forhånd leads** even when she is a modspiller or not the melder (§2.0). **Confirmed 2026-10-26 (Anders).**
- **S5. Jokers at sol:** a led joker wins; one not led is worth nothing; after a led joker the first playing card sets the suit (as ticket 03 C4). No trump, so the bord's joker setting doesn't matter. **Changed 2026-10-26 (Anders):** a led joker wins and leaves **no suit to follow**; every card is legal in that stik.
- **S6. Væltet** = one stik more than allowed (sol 2, ren sol 1). A væltet player keeps playing her cards. The runde stops after the stik where the last sol player is væltet; it does not stop early when the outcome is otherwise settled (e.g. every sol player safe). **Confirmed 2026-10-26 (Anders).** A væltet player plays on.
- **S7. Settlement:** each sol player settles the fixed amount (bord's sol 3 / ren sol 4) with **each modspiller** (those who neither won the melding nor went with): + amount × modspillere if she kept within, − if væltet; each modspiller the opposite per sol player. Sol players never settle with one another. Example: Bent and Carla play sol against two, Bent klarer, Carla væltet: Bent +6, Carla −6, the modspillere 0 each. If all four play sol there is no modspiller and nobody scores. **Changed 2026-10-26 (Anders):** each sol player settles the amount with **all three** other seats, other sol players included: "Bent klarer sig, Carla taber: Bent vinder indsatsen fra 3 personer, Carla taber indsatsen til 3 personer; de to andre taber indsatsen 1 gang men vinder den også 1 gang." Each pair settles once (Anders: "man er ikke på hold sammen i sol"): with sol 3, Bent +9, Carla −9, the two others 0. Equal outcomes settle nothing between them. Same at bordlægger.
- **S8. No doublings** at sol (REGLER names none: no trumfløs, påhæng or bank apply).
- **S9. Result fields:** a sol result's `gik_hjem` is "the melder kept within" and `stik` the melder's stik (only for the shared result shape); the sheet shows each sol player's stik ("1 · 2") and "Klaret" / "Væltet" / "N klaret".
- **S10. A bot standing in** (a player forlod) lays the kitty back (keeps its hand) and plays its first legal card, like ticket 03 C7.

