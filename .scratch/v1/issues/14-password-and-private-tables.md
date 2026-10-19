# 14: Password and private tables

**What to build:** The host chooses the table type. Password tables show in the lobby with a lock and need the password to sit. Private tables are hidden from the lobby and can be reached by their link.

**Blocked by:** 12 (Lobby and open tables)

**Status:** ready-for-agent

Spec: `.scratch/v1/spec.md`

- [ ] Table type is open, password or private
- [ ] Password tables store a password digest. A wrong password gives "Forkert adgangskode" and is a result, not an exception.
- [ ] Private tables are absent from the lobby. Opening the link lets an approved user take a free seat.
- [ ] Table-seam tests cover each type
