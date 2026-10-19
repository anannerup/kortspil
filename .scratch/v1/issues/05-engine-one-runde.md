# 05: Rules engine: one runde without passing

**What to build:** A plain-Ruby hjerterfri engine plays one complete runde from a deal, with no passing: legal moves, stik winners, points and shooting the moon. It is verified by tests alone. This is the deep module that the rest of the game builds on.

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

Spec: `.scratch/v1/spec.md`

- [x] No Rails or ActiveRecord dependency. Deals come from an injected shuffler, so they are deterministic.
- [x] The engine is built from the rules config, the deal and the plays so far. Card codes are rank + suit (`2C`, `TD`, `QS`).
- [x] `apply(seat, intent)` returns the new state or a rejection with a reason. Illegal moves don't raise.
- [x] Enforced rules: the 2♣ holder leads 2♣; follow suit; no hearts or Q♠ in the first stik unless the player has nothing else; hearts can't be led until broken unless the player holds only hearts (source: docs/rules §3.4–3.5)
- [x] The highest card of the led suit wins the stik and leads the next one
- [x] Runde points: 1 per heart, 13 for Q♠. Shooting the moon gives the shooter 0 and the others 26.
- [x] `view_for(seat)` exposes only that seat's hand, the opponents' card counts, the current and last stik, who is to act, the legal moves and hearts-broken. Tests assert that no other seat's cards leak.
- [x] Rebuilding from the stored strings (deal + plays) gives the same state as playing live
