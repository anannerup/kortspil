# 14: Password and private tables

**What to build:** The host chooses the table type. Password tables show in the lobby with a lock and need the password to sit. Private tables are hidden from the lobby and can be reached by their link.

**Blocked by:** 12 (Lobby and open tables)

**Status:** done

Spec: `.scratch/v1/spec.md`

- [x] Table type is open, password or private
- [x] Password tables store a password digest. A wrong password gives "Forkert adgangskode" and is a result, not an exception.
- [x] Private tables are absent from the lobby. Opening the link lets an approved user take a free seat.
- [x] Table-seam tests cover each type

## Comments

- 2026-10-25: Done on branch t13-host-private (together with 13).
  - **Model**: `tables.kind` is `practice`, `open`, `password` or `private`; `tables.password_digest` via `has_secure_password validations: false`. The digest is required for password tables and cleared for every other type. The enum has `scopes: false`, because a scope named `private` would shadow Ruby's `private`; `Table.listed` filters on `LISTED_KINDS` (open, password) itself.
  - **Choosing the type**: the lobby's new-table form and the waiting room's settings both have "Bordtype" (Åbent bord / Med adgangskode / Privat bord) and a password field for the password type. A password table needs a password (`password_missing`: "Skriv en adgangskode til bordet."); in the settings a blank field keeps the current one. Unknown types are refused (`unknown_kind`). The host sees the password as plain text while typing it, since it is meant to be told to others; the joiner's field is a password field.
  - **Joining a password table**: the lobby shows a lock pill ("Adgangskode", inline SVG) and a password field above the seats; every "Sæt dig her" button submits that one form. A wrong or missing password is the refusal `wrong_password` ("Forkert adgangskode."). Someone already seated there may move seats without it. The waiting page itself is visible without the password, like the lobby entry (it holds no secrets).
  - **Private tables**: not in the lobby list; the link opens the waiting room for any approved user, who can take a free seat. The waiting room follows the table on LobbyChannel by `table_id`, which works for every non-practice table.
  - The lobby entry and the table state now carry the kind (`kind` / `table_kind`); the entry never holds the password or digest.
  - Tests: `test/models/table_kinds_test.rb` (table seam), `test/controllers/host_controls_controller_test.rb`, `test/channels/lobby_channel_test.rb`.

