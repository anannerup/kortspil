# 12: Lobby and open tables

**What to build:** Approved users see a live lobby of open tables. They can create a table, choose a seat, sit and stand up, and the host starts the spil when all four seats are filled with humans. Every table has its own URL. A player can sit at only one table at a time. The admin sees the active tables.

**Blocked by:** 06 (Practice table end-to-end)

**Status:** done (branch t12-lobby; not yet merged)

Spec: `.scratch/v1/spec.md`

- [x] The lobby lists open tables with host, seats and status, and updates live over Action Cable
- [x] Create table, choose seat, sit and leave all work before start
- [x] The host can start only when 4 seats are filled. The practice table from 06 still works.
- [x] Every table has a stable URL that opens the table view
- [x] Sitting at a second table is refused with a clear message
- [x] Multiple humans play a spil together, each receiving only their own hand
- [x] The admin page lists the active tables
- [x] Table-seam tests cover seating, the one-table rule and the start condition with several humans

## Comments

- 2026-10-20, Anders: a player can leave a spil with other humans at any time, and leaving before the end means **they lose the spil**. The confirmation says "Forlad bordet? Du taber spillet." The leaver is recorded as forfeiting, so stats count it as a loss. Confirmed by Anders: by default a bot takes over the seat so the others can finish, and the result marks the leaver as the loser regardless of points. The word "by default" leaves room for a table option later.
- [ ] Leaving mid-spil asks for confirmation, records the leaver as forfeiting (a loss), hands their seat to a bot, and lets the others continue
- 2026-10-20: the leaving rules were settled in a grilling and moved to ticket 19 (which also handles them for this ticket's multiplayer bord). The box above is now covered by 19.
- 2026-10-25: Done on branch t12-lobby.
  - **Commands** (`TableCommands`): `create_table` (open table, creator is vært in seat 0, rules from the same form as Øvebord), `sit` (take a free seat or move to another), `start` (vært only, every seat taken), and `leave` before the start is standing up. Refusals are explicit results (`Outcome#refusal`: `seated_elsewhere`, `seat_taken`, `no_such_seat`, `not_waiting`, `not_host`, `seats_not_filled`), with Danish texts in `config/locales/da.yml` (`tables.refusals`).
  - **Seating** (`Table::Seating`): `refusal_to_sit`, `sit!`, `stand!`, `full?`. One bord per user is checked against borde that are not closed, practice tables included, so Øvebord and Opret bord are refused too while the user sits somewhere.
  - **Lobby**: `LobbyChannel` streams the list of open tables (vært, status, rules, seats). `Table` and `Seat` broadcast it again in `after_commit`. The React lobby lists them with a "Sæt dig her" button on each free seat. One rules form has two buttons: "Opret bord" and "Øvebord". The rules are shown on every listed table and on the waiting page, which also covers 09's "rules shown before sitting down".
  - **Table URL** `/tables/:id`: while waiting, it shows the waiting page (`app/frontend/lobby/WaitingRoom.tsx`, live from LobbyChannel), where anyone may sit, the seated can stand up ("Rejs dig") and the vært starts. When the spil starts, the page reloads into the existing table page. A player who isn't seated at a started open table goes back to the lobby with a message. Practice tables still give 404 to anyone else.
  - **Admin**: "Aktive borde" lists every table that isn't closed (type, vært, players, status).
  - Decided here, beyond the ticket: when the vært stands up before the start, the next human in seat order becomes vært, and the bord closes when its last human stands up. Without this, a bord would get stuck. Ticket 13 still owns kick, bots and handover during a spil.
  - Interim until ticket 19: leaving a spil in progress at an open table forfeits it for the leaver and closes the bord for everyone (everyone gets "closed"), as on the practice table. No bot takeover yet. Leaving after a finished spil also closes the bord.
  - Not browser-tested with several real clients. Covered by `test/models/open_tables_test.rb` (table seam), `test/controllers/open_tables_controller_test.rb`, `test/channels/lobby_channel_test.rb` and the admin dashboard test.
