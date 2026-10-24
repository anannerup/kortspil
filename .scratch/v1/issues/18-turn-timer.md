# 18: Turn timer and keep-alive

**What to build:** The server always knows whether each seated human is connected and acting. Clients keep a heartbeat with the server, so a closed tab or a dropped network is noticed within seconds rather than minutes. When it is a human's turn and they don't act, they get a warning at 30 seconds. At 60 seconds the table raises a "forladt" event for that seat, which is handled in 19.

**Blocked by:** 12 (Lobby and open tables)

**Status:** done

Spec: `.scratch/v1/spec.md`. The rules come from the leaving grilling on 2026-10-20; see GLOSSARY.md (Forlade, Frakoblet).

- [x] The client sends a heartbeat every few seconds over the table channel. The server treats a seat as frakoblet as soon as the channel closes or heartbeats stop (for example after about 10 s of silence). Half-open connections are caught this way too.
- [x] Timers are driven by clock-tick commands with an injected clock. No real sleeps in tests.
- [x] Frakoblet: the 60-second clock starts the moment the connection is lost, whether or not it is the seat's turn. The spil keeps going until it's that seat's turn, then waits for the time that remains.
- [x] Connected but inactive on their turn: a warning goes to that player at 30 s. At 60 s the seat counts as forladt.
- [x] A frakoblet player who comes back inside the 60 s keeps their seat. The clock is cancelled and the spil carries on.
- [x] The others see "Venter på Anders… 0:42" with a live countdown, and the spil pauses only while it's that seat's turn
- [x] Bots are exempt
- [x] Table-seam tests cover heartbeat loss, reconnect at 59 s, expiry at 60 s, disconnect when it's not their turn, and the inactive warning at 29, 30 and 60 s

## Comments

- 2026-10-25: Done on branch t18-timer-leaving, together with 19.
  - **Clock** (`TurnClock`, plain Ruby): given each human seat's heartbeat, (re)connect, frakoblet and warning times and whom the spil waits for, it says who is lost, who is due a warning, who has forladt, the seconds left per seat and when the next check is. No clock of its own: `TableCommands` gets `clock:` (default `Time`) and passes `now` in. Tests use `FakeClock` and `FakeScheduler#ticks`; nothing sleeps.
  - **Commands**: `connect`, `heartbeat`, `disconnect` and `tick(game_id:)`. `TableChannel` maps subscribe, the `heartbeat` action and unsubscribe onto them. The tick runs as `TableTickJob` (`TableScheduler.tick`) at the time of the next check. `games.tick_at` keeps it to one chain of ticks per spil: a tick is only scheduled when no earlier one is pending.
  - **Stored**: `seats.heartbeat_at`, `connected_at`, `disconnected_at` and `warned_at` (written with `update_all`, so heartbeats don't refresh the lobby), and `games.turn_started_at` and `tick_at`.
  - **Heartbeat**: the client sends one every 4 s while connected (`tableSubscription.ts`). 10 s of silence makes the seat frakoblet, counted from its last heartbeat. A closed subscription makes it frakoblet at once. A heartbeat from a seat the clock had marked lost brings it back.
  - Decided: **only open tables have a clock.** A practice table waits for its player as long as it takes: nobody else is waiting, and leaving it still works as in 08.
  - Decided: **the 60 s of a frakoblet seat run whether or not it is that seat's turn.** At 60 s it has forladt and a bot takes over, even if that seat isn't to act. The ticket's "the spil keeps going until it's that seat's turn, then waits for the time that remains" holds: the spil only pauses while it's that seat's turn, and then only for what's left of the 60 s.
  - Decided: the pass counts as everyone's turn from the deal. Every human who hasn't passed is warned at 30 s and has forladt at 60 s. A play, a moon choice or the end of the pass starts the next wait. A non-final pass does not restart the others' clocks.
  - Decided: a frakoblet seat on its turn has forladt at the **earlier** of its two deadlines (60 s from the loss, 60 s from the start of its wait). **Coming back restarts the wait on the turn**, so a player back at 59 s isn't counted as gone a second later.
  - The state now carries `seats[].frakoblet`, `seats[].seconds_left` (counted from when the message was built; the client counts down from when it arrived) and `timer: {warning, limit}`. The warning is `{type: "turn_warning", seconds_left}`, sent only to that player.
  - UI: a bar along the lower edge of each name tag runs down while a clock runs for that seat. The tag turns red from the warning. A frakoblet player's tag is grey with "· frakoblet 0:42". You get a red toast "Din tur — 30 sekunder tilbage". The status line shows "Venter på Anders… 0:42" when the player the spil waits for is frakoblet or past the warning.
  - Tests: `test/models/turn_clock_test.rb` (the rules as data) and `test/models/table_absence_test.rb` (table seam: heartbeat loss, reconnect at 59 s, expiry at 60 s, a disconnect when it's not their turn, the warning at 29/30/60 s, the pass clock, bots and practice exempt, tick scheduling), plus channel smoke tests for heartbeat and unsubscribe.
  - Not checked in a browser with real clients (no dev server, to save memory); TypeScript is strict-clean.
