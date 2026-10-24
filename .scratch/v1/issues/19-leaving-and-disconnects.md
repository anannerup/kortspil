# 19: Leaving and disconnects

**What to build:** A player can leave a spil that is in progress at any time with "Forlad bordet" (confirmed inline: "Forlad bordet? Du taber spillet."). Not coming back within 60 seconds of being frakoblet, or not acting for 60 seconds on one's turn (from ticket 18), counts the same. Either way the player has **forladt** the spil and lost it. A bot takes over the seat (at once on active leave, after the 60 s otherwise), and the spil is played to the end. The player can't return to that spil. The winner is the human with the lowest total; a bot can never win. A player who is frakoblet sees an impossible-to-miss banner at the top of the lobby saying their spil is waiting, with a countdown and a "Tilbage til bordet" button. There is no vote; that replaces the earlier voting design.

**Blocked by:** 12 (Lobby and open tables), 18 (Turn timer and keep-alive)

**Status:** done

Spec: `.scratch/v1/spec.md`. The rules come from the leaving grilling on 2026-10-20; see GLOSSARY.md (Forlade, Frakoblet, Vinder, Afbrudt).

- [x] "Forlad bordet" works in a multiplayer spil. A bot takes over the seat immediately (it acts at once if it is that seat's turn, including passing). The leaver is recorded as having forladt.
- [x] The "forladt" event from 18 does the same after 60 s
- [x] Every takeover is appended to `seat_log` (`{seat, from, to, at_play}`), and the seat is shown as "Bot (overtog fra Anders)". The seat keeps its running totals.
- [x] A player who has forladt can't rejoin that spil. They can sit down again for the next spil at the bord, if there's a free seat.
- [x] Result: every player who forlod gets a loss, whatever their points. The vinder is the human (or humans, on a tie) with the lowest total, and a human who ties with a bot still wins. If a bot alone has the lowest total, there's no vinder. Wins count normally.
- [x] When the last human leaves, the spil is stored as afbrudt (unfinished) and the bord closes. That last leaver still gets a loss.
- [x] Leaving before the spil starts, or after it's finished, is just standing up, with no loss
- [x] Øvespil never count in statistics. Leaving a practice bord already works from ticket 08 and stays as it is.
- [x] When the vært leaves, the next human becomes vært (shared with ticket 13)
- [x] Lobby banner: a frakoblet player sees "Dit spil er i gang — de venter på dig (0:42)" at the top of the lobby, with a "Tilbage til bordet" button. The "Ved bordet" marker in the nav stays.
- [x] Table-seam tests cover active leave (with an immediate bot move on their turn and during passing), the 60-s forladt path, no rejoin after forladt, the winner rule (human lowest, a human tied with a bot, a bot lowest means no vinder, human ties), the last human leaving means afbrudt, leaving before start and after finish, and `seat_log` contents. Request test for the banner.

## Comments

- 2026-10-25: Done on branch t18-timer-leaving, together with 18.
  - **Forlade** (`TableCommands#forlade`, used by "Forlad bordet" and by the clock): under the game's lock, a bot takes the seat (`Seating#take_over!`, appended to `seat_log` as `{seat, from, to, at_play}` with `at_play` = `LiveGame#version`). If the bot is to act (its turn, the pass, the moon choice), it acts at once in the same command. The leaver gets `{type: "forladt"}`. Their page reloads, and the bord's URL sends them to the lobby with "Du har forladt spillet ved det bord og kan ikke vende tilbage til det." The seat keeps its totals, since totals belong to the seat.
  - The state shows such a seat as `took_over_from: "Anders"`, and its tag reads "Bot (overtog fra Anders)".
  - **No rejoin**: the seat now belongs to the bot, so connect, heartbeat and the channel subscription all give nothing, and the table URL redirects. The leaver is free to sit at any other bord.
  - **Result** (`Game#forladt_ids`, `Game#winner_ids`, `Game#holders`): everyone in the `seat_log` plus `forfeited_by` has forladt and lost. The vindere are the seats a human still holds that have the lowest total, so a human tied with a bot wins, and a bot alone on the lowest total means no vinder. `score.winners` in the state follows the same rule (`engine_game.winners & game.human_seats`). That changes practice tables too: a bot can never be shown as the winner. GameOver then says "Ingen vinder — en bot fik færrest point". Nothing extra is stored; statistics can read the result from these rows.
  - **Last human**: when the last human forlader (actively or by the clock), the spil is `abandoned` (afbrudt) with `forfeited_by` = them, and the bord closes. This is the same path as leaving a practice table, which therefore stays as it was in 08.
  - **Vært** handover when the vært forlader mid-spil: the next human in seat order (`Seating#hand_over_host`, shared with standing up before the start).
  - **Before the start**: standing up, as in 12. **After the end**: standing up, with no loss. Decided here: at an open table where other humans remain, the bord goes back to `waiting` (so the empty seat can be taken for the next spil), and the others get `{type: "waiting"}`, which reloads them into the waiting room. Before this, leaving after the end closed the bord for everyone. Ticket 13 (bots, kick) may want to refine that waiting room; seats a bot took over stay with the bot until then.
  - **Lobby banner** (`home/show.html.erb`, `Table#seconds_to_return`): "Dit spil er i gang — de venter på dig (0:42)" with "Tilbage til bordet", counted down live by `app/frontend/app/countdown.ts`. It shows whenever the player sits in a spil in progress at an open bord. If they aren't marked frakoblet yet, they are counted as frakoblet from now. This is on purpose: going from the table to the lobby closes the socket only after the lobby page has loaded. The "Ved bordet" marker stays.
  - Confirm text: "Forlad bordet? Du taber spillet, og en bot overtager din plads. Du kan ikke vende tilbage til dette spil." On a practice table it says "Forlad bordet? Spillet slutter her."
  - Øvespil: nothing counts statistics yet (statistics are out of v1). The result methods above work for practice games too, so the future statistics must skip `tables.kind = practice`.
  - Tests: `test/models/table_absence_test.rb` (active leave with an immediate bot move on their turn and during the pass, the 60 s path, no rejoin, the vært handover, the last human leaving actively and passively, leaving after the end, `seat_log` contents and totals kept), `test/models/game_result_test.rb` (the winner rule: human lowest, human ties, a human tied with a bot, a bot lowest means no vinder, a leaver with the lowest total, afbrudt), and `test/controllers/leaving_controller_test.rb` (the banner, Forlad bordet over HTTP, no way back).
