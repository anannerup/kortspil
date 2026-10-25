# 21: Bot levels (Let, Mellem, Svær)

**What to build:** Replace the provisional `Hjerterfri::Bot` heuristics with the strategy agreed with Anders in ticket 20. There are three levels, layered so each can do everything the one below can (Let ⊂ Mellem ⊂ Svær). Bots act immediately, with no deliberate delay. A bot tournament measures the levels. The spec is `docs/bots/hjerterfri-strategy.md`; the decisions and sources are in `docs/research/hjerterfri-bot-strategy.md`.

**Blocked by:** None (can start immediately). Choosing a level in the UI is ticket 22.

**Status:** in-progress

- [ ] Engine: `Round#view_for` also exposes some public information: all completed stik in this runde (seat and card per play, plus the winner), `points_taken` per seat, and the bord's rule toggles. The table layer (`LiveGame`) passes spil totals and `end_score` to the bot. A test shows the view never contains another seat's cards.
- [ ] `Bot` takes a level (`:let`, `:mellem` or `:svaer`) and an injected `random:`. It still chooses only from `legal_moves`. The no-illegal-move test over many seeded deals runs for every level.
- [ ] Let follows spec §4. It tries to win with simple rules: no memory and no plan, but never absurd. It passes Q♠ when it holds fewer than 3 other spades.
- [ ] Mellem follows spec §5: passing to make a void, remembering its own pass, tracking whether Q♠ has been played, flushing Q♠, shedding cards on clean stik, playing for J♦ −10 when that toggle is on, and blocking the moon.
- [ ] Svær follows spec §6: full card counting and void inference, exit cards, and shooting the moon only with a clear moon hand (giving up on the first lost penalty card). It plays the endgame on the score: it protects itself, ends the spil when it leads and attacks the leader. It doesn't know that bots can't be vinder.
- [ ] Variance per level is fixed in code (spec §3) and deterministic under a seeded `random:`.
- [ ] The deliberate bot delay (`Bot#delay`, 0.8–1.2 s) is removed. Bots act immediately, and the client's animations set the pace.
- [ ] Bot tournament script and test: N seeded spil (e.g. 1,000) with levels rotated across seats. It reports average points per runde per level, with the expectation Svær < Mellem < Let. The numbers go to Anders, and the [valgt] rules are tuned if the order fails.

## Comments

- Keep the heuristics game-neutral where the spec does (ducking, voids, exit cards, counting) so they can be reused for sol, ren sol og bordlægger in es-makker. Parts that are only for hjerterfri are marked [hjerterfri].
- Monte Carlo search is out of scope. Revisit it only if the tournament shows that rules aren't strong enough for Svær.
- The numbers marked [valgt] in the spec (moon hand, moon threat ≥ 10, "late" = ≤ 4 cards) are the first things to tune.
