# 18: Turn timer and keep-alive

**What to build:** The server always knows whether each seated human is connected and acting. Clients keep a heartbeat with the server, so a closed tab or a dropped network is noticed within seconds rather than minutes. When it is a human's turn and they don't act, they get a warning at 30 seconds. At 60 seconds the table raises a "forladt" event for that seat, which is handled in 19.

**Blocked by:** 12 (Lobby and open tables)

**Status:** ready-for-agent

Spec: `.scratch/v1/spec.md`. The rules come from the leaving grilling on 2026-10-20; see GLOSSARY.md (Forlade, Frakoblet).

- [ ] The client sends a heartbeat every few seconds over the table channel. The server treats a seat as frakoblet as soon as the channel closes or heartbeats stop (for example after about 10 s of silence). Half-open connections are caught this way too.
- [ ] Timers are driven by clock-tick commands with an injected clock. No real sleeps in tests.
- [ ] Frakoblet: the 60-second clock starts the moment the connection is lost, whether or not it is the seat's turn. The spil keeps going until it's that seat's turn, then waits for the time that remains.
- [ ] Connected but inactive on their turn: a warning goes to that player at 30 s. At 60 s the seat counts as forladt.
- [ ] A frakoblet player who comes back inside the 60 s keeps their seat. The clock is cancelled and the spil carries on.
- [ ] The others see "Venter på Anders… 0:42" with a live countdown, and the spil pauses only while it's that seat's turn
- [ ] Bots are exempt
- [ ] Table-seam tests cover heartbeat loss, reconnect at 59 s, expiry at 60 s, disconnect when it's not their turn, and the inactive warning at 29, 30 and 60 s
