# 13: Host controls

**What to build:** The host can kick a player and add or remove bots before the spil starts. If the host leaves, host passes to the next human. A table with no humans left closes on its own.

**Blocked by:** 12 (Lobby and open tables)

**Status:** done (branch t13-host-private; not yet merged)

Spec: `.scratch/v1/spec.md`

- [x] Kick, add bot and remove bot work only before start, and only for the host
- [x] When the host leaves, host passes to the next human in seat order
- [x] A table with no humans closes and disappears from the lobby
- [x] Table-seam tests cover each of the above

## Comments

- 2026-10-25: Done on branch t13-host-private (together with 14).
  - **Commands** (`TableCommands`): `kick`, `add_bot`, `remove_bot` and `change_settings` (rules and table type), all for the vært only and only while the table waits. Refusals are results: `not_host`, `not_waiting`, `no_such_seat`, `seat_taken`, `nobody_to_kick`, `no_bot_there` (Danish texts in `tables.refusals`; `not_host` now reads "Det kan kun værten." since it covers more than the start).
  - **Seating**: `seat_bot!`, `empty!`, `refusal_to_fill` and `pass_host_on!`. Bots get the lowest free "Bot N" name. A spil starts with any mix of humans and bots once all four seats are taken; the bots are scheduled as at the practice table.
  - **Kick is not a ban** (spec: "fix a mistaken join"): the kicked player may sit down again. Their waiting room shows "Værten har fjernet dig fra bordet." The vært cannot kick themself (they stand up instead), and bots are removed, not kicked.
  - **Rules between spil**: rules may now change whenever the table waits (the lock is "while a spil is dealt/played", not "once any spil existed"), so a vært can change them after a spil, when the table is back in the waiting room.
  - **Host handover**: standing up before the start already handed over (ticket 12). `Seating#take_over!` now also hands the vært role to the next human, so when ticket 19 lets a bot take over a leaving vært's seat mid-spil, handover works without more code. Covered in `test/models/table/seating_test.rb`. Mid-spil leaving itself still closes the bord until 19 lands.
  - **Auto-close**: a bord whose last human stands up (bots or not) closes and leaves the lobby.
  - **"Spil igen" at multiplayer tables**: each human chooses "Spil igen"; the next spil starts with the same seats and the table's rules once every human at the table has chosen it (stored in `games.play_again_by`, shown as `play_again_seats` in the state: "Venter på, at Erik vælger Spil igen…"). At a practice table the one human's click starts it at once, as before. Decided so that nobody is pulled into a new spil they cannot leave without losing it.
  - **Leaving after a finished spil** (not a forfeit): the seat is freed, the bord goes back to *waiting*, the vært role passes on if needed, and the others get a `waiting` message that reloads their page into the waiting room, where the vært can fill the seat with a bot or wait for someone. The last human leaving closes it. (Before, this closed the bord for everyone.)
  - **UI** (waiting room, `app/frontend/lobby/`): per-seat "Fjern" (with confirmation), "Sæt en bot her" and "Fjern bot" for the vært; an "Indstillinger" panel with the same rules/type fields as the lobby (`TableSettingsFields`); invite panel with the link and "Kopiér link". Big `.btn` buttons from application.css. The waiting room now follows its own table on LobbyChannel (`table_id` param), so it also works for private tables.
  - Tests: `test/models/host_controls_test.rb` (table seam), `test/controllers/host_controls_controller_test.rb`, `test/channels/lobby_channel_test.rb`. Waiting room and lobby looked at in a headless browser (desktop and phone width); the "Spil igen" waiting note was not browser-tested.

