# 06: Gode and halve

**What to build:** At gode, clubs is trump (the melder doesn't name it). At halve the melder calls an ace ("jeg er makker til …"), the ace holder reveals themselves at once, names trump (a suit other than the called ace's) and takes the kitty; if the ace is in the kitty the melder is selvmakker and plays alone. Both doublings already count via 05.

**Blocked by:** 03

**Status:** done

- [x] Gode: clubs trump.
- [x] Halve: reveal, partner's trump ≠ ace suit, partner takes the kitty; ace in kitty → selvmakker.
- [x] The halve esmakker is visible to all from the reveal.
- [x] Engine and Table tests; UI for the halve partner's choices.

## Comments

### Built (branch `esmakker-06`)

- **Gode** was already played by ticket 03 (clubs trump; the melder is never asked, she only calls the ace and takes the kitty). Verified in the engine and UI and covered by a new test.
- **Halve** is played by `Esmakker::Play` (no longer "ikke spillet"): `:calling_ace` (the melder) → `:choosing_trump` → `:discarding` (both the `declarer`'s) → `:playing` → `:complete`. The `declarer` is the ace's holder, or the melder when she is selvmakker. Same intents and log tokens as ticket 03 (`esD`, `trumfH`, `kast-…`); the runde replays from the log. New refusal `trump_is_ace_suit`.
- Every seat knows the esmakker (or that the melder is selvmakker) from the ace call on: views, side stik, the name tag "makker" / "melder · alene".
- No new bord actions: `Table#call_ace`, `#choose_trump` and `#discard` (and the `TableChannel` actions of the same names) already act for the seat the engine says is to act, so the makker uses them as they are.
- UI: the panel says "Jeg er makker til …" over the melder's ace choice and "Vælg trumf (ikke <farve>)" over the makker's (or the selvmakker's); the middle of the table words who does what (`play.ts`, `declarationText`, node tests).
- Tests: `test/models/esmakker/gode_halve_test.rb` (engine), `test/models/esmakker_halve_table_test.rb` (a whole halve runde through the bord, and the selvmakker path).

### Valg — for Anders to confirm

- **D1. Trumfløs at halve is allowed.** REGLER says the makker names "en anden farve end det kaldte es"; §2.0 also says trumfløs may be chosen whenever trump is named, so the makker may name trumfløs.
- **D2. The selvmakker at halve may not name the called ace's suit either.** REGLER (§2 Halve) only says she "bestemmer da selv trumf"; I kept the halve rule (trump ≠ the ace's suit) for her too, so the choices are the same whoever names trump.
- **D3. Order: trump first, then the kitty**, for the makker and the selvmakker alike (REGLER's order: "giver sig til kende, vælger trumf og bytter med katten"). So trump is named before the kitty is seen, as at an ordinary melding (03 C2).
- **D4. Who leads stik 1 at halve: the melder**, as at every stik melding (REGLER "Første udspil"), not the makker who named trump.
- **D5. A halve melder holding all four aces** calls any of them and is selvmakker (as 03 C3).
- Ticket 04 note: fordækt at halve — the melder does not take the kitty at halve, so "efter byttet" is her own 13 cards.
