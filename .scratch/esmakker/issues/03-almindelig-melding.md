# 03: An ordinary melding played through

**What to build:** The first complete runde. The melder of an ordinary melding names trump (any suit or trumfløs), calls an ace they don't hold, takes the kitty up and discards three cards nobody sees, and leads the first stik. Stik are played with following suit and trump; the esmakker stays hidden until the called ace is played. The melding goes home when melder and esmakker together take at least the bid number of stik (selvmakker alone if the ace was in the kitty). The runde result (gik hjem / bet, stik taken) is shown, the next runde is dealt, and the spil ends after the bord's number of runder with a final overview (points come in 05).

**Blocked by:** 02

**Status:** done

- [x] Trump or trumfløs; the called ace must not be in the melder's hand; ace in the kitty → selvmakker.
- [x] Kitty pickup and discard of three hidden cards.
- [x] Melder leads; follow suit; trump beats; trumfløs has no trump.
- [x] Per-seat views hide the esmakker until the ace falls, and hide others' hands and the discarded kitty.
- [x] Gik hjem / bet decided; next runde; spil ends after N runder.
- [x] Engine and Table tests; the per-seat view never leaks hidden cards or the esmakker.

## Comments

### Built (branch `esmakker-03`)

- `Esmakker::Play` runs the runde after the meldingsrunde for a stik melding: `:choosing_trump` → `:calling_ace` → `:discarding` → `:playing` → `:complete`. Intents `ChooseTrump`, `CallAce`, `Discard`, `PlayCard`, logged as `trumfH` / `trumftrumfloes`, `esD`, `kast-2C-3D-X1` and the card's code; the runde replays from the log. `Trick` decides the stik, `LegalMoves` what may be played, `RundeResult` how it ended (gik hjem / bet, stik per seat; points 0 until ticket 05).
- Bord actions `Table#choose_trump`, `#call_ace`, `#discard` (and the same `TableChannel` actions); `Table#play` plays a card at both games. The last runde ends the spil through `Playing#spil_over` (new waiting bord, `next_path`), as hjerterfri now does.
- The state's `score.results` holds every completed runde's result for the overview. The esmakker in it is public once a runde is over.

### Valg — for Anders to confirm

- **C1. Påhæng and sol-meldinger before their tickets.** Gode is played now: clubs are trump, the melder only calls the ace (the rest is as an ordinary melding; its doubling is ticket 05). Halve, vip and the sol-meldinger end the runde at once as **"ikke spillet"**: the result says the melding comes in a later version, the runde counts toward the bord's runder, scores 0, and the next runde is dealt. No redeal, so the spil never stalls.
- **C2. The kitty is taken up with the ace call.** No separate "tag katten" step: calling the ace puts the three cards in the melder's hand (ringed for her only), so the ace is always called before she sees the kitty and selvmakker stays an accident.
- **C3. A melder holding all four aces** may call any ace and is selvmakker (REGLER is silent; otherwise she could not go on).
- **C4. Jokers until ticket 04:** playable at any time (also when you could follow suit); a led joker wins the stik; a joker not led is worth nothing. After a led joker, the **first playing card sets the suit to follow** (REGLER says nothing about it). The bord's "joker kan stikkes med trumf" setting is not used yet (ticket 04).
- **C5. Who knows the esmakker:** the esmakker herself from the start; the melder once she is selvmakker (she took the kitty); everyone once the called ace is played, or when the runde is over. Stik per seat are public; stik per side are shown only to a seat that knows the sides.
- **C6. The melder's discarded cards** stay hidden from the others, also after the runde.
- **C7. A bot that takes over a seat** (a player forlod) plays the runde's default: pas, clubs, the first ace it may call, the kitty laid back, the first legal card. Only so the spil is never stuck; ticket 11/12 decide.
- Ticket 04 hooks: the called ace's rules go in `LegalMoves.for` (it already receives the trick; it needs the called ace and the hand), the joker trump setting in `Trick#winner`.
