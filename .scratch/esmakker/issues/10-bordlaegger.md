# 10: Bordlægger and ren bordlægger

**What to build:** Bordlægger (after 11 with påhæng) and ren bordlægger (after 12 with påhæng) play like sol and ren sol, except that the melder's cards are laid open for the opponents after the first stik. Fixed values bordlægger 5, ren bordlægger 6 (inferred defaults, bord setting).

**Blocked by:** 09

**Status:** done

- [x] Ladder places; open cards after stik 1 in every opponent's view.
- [x] Fixed points.
- [x] Engine tests; UI shows the open hand.

## Comments

### Built (branch `esmakker-10`)

- `Esmakker::SolPlay::PLAYED` holds all four sol-meldinger; `OPEN_HAND` the two bordlæggere. `SolPlay#open_hand` is `{ seat: melder, cards: [...] }` from the end of the first stik (the melder's cards as she holds them now, in sol order, each card leaving as she plays it), nil before that and at sol / ren sol. It is in every seat's view (`play.open_hand`). Everything else is ticket 09's sol: gå med, kitty order, forhånd leads, ace lowest, væltet, played to the end, early stop.
- Scoring: `SolResult.settled` → `Scoring.sol_points` with the bord's `bordlaegger` / `ren_bordlaegger` amounts (standard 5 / 6, inferred).
- **"Ikke spillet" is gone.** Every melding is played now (Play: no påhæng, gode, halve, vip; SolPlay: the four sol-meldinger), so `RundeResult.not_played`, Round's fallback to it and the client's `not_played` kind/branches are removed; Round raises on a melding no play takes (corrupt data). Of its tests: the sol_play and scoring ones are deleted; the round test now checks that a bordlægger melder starts the play (`:exchanging`); the play-table "short spil" and points-table tests play a real bordlægger runde (the points one with the vært's bordlægger 7). Note: an es-makker spil stored before this change with a bordlægger runde would now replay that runde as unfinished (as ticket 09 did for sol) — fine as long as es-makker isn't live with such data.
- UI: `openHandAt` / `openHandLabel` in `sol.ts` (node-tested). The table page shows the open hand in place of the melder's card backs (`OpenHand`, `.esmakker-open-hand-*`): a row at north, a column at west/east, overlapped so rank and suit show; the melder herself sees her hand as always. Screenshots (before stik 1 hidden, open north, open east, result), 1400×900 and 400 px.
- Tests: `test/models/esmakker/bordlaegger_test.rb` (hidden during the exchange and during stik 1, open in all four views after it, cards leave as played; only the melder's hand with someone going with; sol/ren sol lay nothing open; ren bordlægger væltet on one stik; the bord's values; 30 random runder checking the open hand at every step, zero sum and replay), `test/models/esmakker_bordlaegger_table_test.rb` (a whole bordlægger runde through the bord with frida going with), `sol.test.ts`.

### Valg — for Anders to confirm

- **B1. Whose hand is laid open when others go with?** Only the melder's (REGLER §2.0/§2.10: "Melderens kort lægges åbent"). Those who went with play their bordlægger with hidden cards. Should their hands be open too?
- **B2. "Efter første stik", not "efter første udspil".** §2.0 says after the first stik; §2.10 (Whistklubben) says after the first udspil. §2.0 wins: the hand opens when stik 1 is taken.
- **B3. Open for everyone**, including those who went with (they are not modspillere, but it is on the table).
- **B4. The melder still exchanges** with the kitty first (as at sol, S1/S2); the cards she lays away are never shown.
