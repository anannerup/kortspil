# 10: Real bots

**What to build:** Bots play a simple, sensible strategy instead of random cards. They act after a short delay so humans can follow, and they are clearly labelled.

**Blocked by:** 07 (Passing)

**Status:** in-progress

Spec: `.scratch/v1/spec.md`

- [x] Passing: Q♠ (unless well protected by other spades), then the highest hearts, then other high cards
- [x] Following suit: play the highest card that still loses the stik, otherwise the lowest
- [x] When void: dump Q♠, then the highest heart, then the highest card
- [x] Leading: the lowest card of a safe suit
- [x] Bots only ever choose from the legal moves they are given. A test plays many seeded deals and finds no illegal move.
- [x] The bot delay is about 0.8–1.2 s and is injectable in tests
- [ ] Bots are labelled "Bot" in the seat

## Comments

- Strategy is `Hjerterfri::Bot` (`app/models/hjerterfri/bot.rb`): `choose_play(view)`, `choose_pass(hand)`, `delay(random:)`. Q♠ counts as guarded with 4+ lower spades. The view has no card history, so the bot treats Q♠ as still out unless it holds it.
- `choose_pass` returns card codes only; wiring it to the passing intent (ticket 07) remains.
- Remaining: the table layer that schedules bots after `delay` and the "Bot" label in the seat (UI).

- **Provisional.** Anders wants to own the bot strategy and be grilled on it. The heuristics above are placeholders. See ticket 20. Don't extend or tune the strategy without him.
- Superseded: the strategy is now decided (ticket 20) and is built in tickets 21 and 22. The UI box "labelled Bot in the seat" moves to 22.
