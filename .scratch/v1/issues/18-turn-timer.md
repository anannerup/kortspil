# 18: Turn timer

**What to build:** If the player to act hasn't moved within 30 seconds, they get a warning. At 60 seconds the table signals that a vote should open (handled in 19).

**Blocked by:** 12 (Lobby and open tables)

**Status:** ready-for-agent

Spec: `.scratch/v1/spec.md`

- [ ] Timers are driven by clock-tick commands with an injected clock. No real sleeps in tests.
- [ ] The warning is sent only to the player to act, and only if they are online
- [ ] At 60 s an "inactive" event is emitted for the seat
- [ ] Bots are exempt
- [ ] Table-seam tests cover 29 s, 30 s and 60 s
