# 03: An ordinary melding played through

**What to build:** The first complete runde. The melder of an ordinary melding names trump (any suit or trumfløs), calls an ace they don't hold, takes the kitty up and discards three cards nobody sees, and leads the first stik. Stik are played with following suit and trump; the esmakker stays hidden until the called ace is played. The melding goes home when melder and esmakker together take at least the bid number of stik (selvmakker alone if the ace was in the kitty). The runde result (gik hjem / bet, stik taken) is shown, the next runde is dealt, and the spil ends after the bord's number of runder with a final overview (points come in 05).

**Blocked by:** 02

**Status:** ready-for-agent

- [ ] Trump or trumfløs; the called ace must not be in the melder's hand; ace in the kitty → selvmakker.
- [ ] Kitty pickup and discard of three hidden cards.
- [ ] Melder leads; follow suit; trump beats; trumfløs has no trump.
- [ ] Per-seat views hide the esmakker until the ace falls, and hide others' hands and the discarded kitty.
- [ ] Gik hjem / bet decided; next runde; spil ends after N runder.
- [ ] Engine and Table tests; the per-seat view never leaks hidden cards or the esmakker.
