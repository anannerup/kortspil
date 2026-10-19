# 10: Real bots

**What to build:** Bots play a simple, sensible strategy instead of random cards. They act after a short delay so humans can follow, and they are clearly labelled.

**Blocked by:** 07 (Passing)

**Status:** ready-for-agent

Spec: `.scratch/v1/spec.md`

- [ ] Passing: Q♠ (unless well protected by other spades), then the highest hearts, then other high cards
- [ ] Following suit: play the highest card that still loses the stik, otherwise the lowest
- [ ] When void: dump Q♠, then the highest heart, then the highest card
- [ ] Leading: the lowest card of a safe suit
- [ ] Bots only ever choose from the legal moves they are given. A test plays many seeded deals and finds no illegal move.
- [ ] The bot delay is about 0.8–1.2 s and is injectable in tests
- [ ] Bots are labelled "Bot" in the seat
