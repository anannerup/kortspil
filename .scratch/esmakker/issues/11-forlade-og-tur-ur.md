# 11: Leaving and the turn clock at es-makker

**What to build:** Decided with Anders on 2026-10-26. Leaving an es-makker spil in progress works as at hjerterfri: the player who forlader (actively, or frakoblet past the turn clock) has lost, and a bot takes over the seat and plays on (es-makker bots: ticket 12). The turn clock is the same as at hjerterfri (warning at 30 s, forladt at 60 s), also in the meldingsrunde and the declaration. Until ticket 12 is done there is no es-makker bot to take over; in that case the spil is afbrudt.

**Blocked by:** 03, 12

**Status:** ready-for-agent

- [ ] Forlade at es-makker: the leaver loses; a bot (ticket 12, level Let as at hjerterfri) takes the seat and plays on.
- [ ] Turn clock as at hjerterfri in every phase of an es-makker runde.
- [ ] The leave confirmation explains the consequence.
- [ ] Table tests with fake scheduler/clock.
