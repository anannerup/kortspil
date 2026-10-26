# 02: "Vis kort"

**What to build:** An admin at a bord where every other seat is a bot can switch "Vis kort" on: the bots' hands show face up, and each bot decision shows a line with what the bot intends (es-makker: intended melding, expected stik for itself and makker, guessed makker, expected runde points; hjerterfri: whatever the bot reports). Built once in the shared table shell; each game supplies its own lines. Never visible to non-admins or at a bord with another human. Does not change what the bot knows. See docs/bots/esmakker-strategy.md §5.

**Blocked by:** 01

**Status:** ready-for-agent

- [ ] Server only sends bot hands/lines to an admin at an all-bot bord (test both refusals).
- [ ] Works at hjerterfri and es-makker.
