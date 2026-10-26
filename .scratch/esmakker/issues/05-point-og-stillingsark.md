# 05: Points and the score sheet

**What to build:** Every runde is scored by REGLER §2.0 "Point": a melding that goes home wins (stake + overstik) × doublings, bet loses stake × missing stik × doublings; stakes 8 = 1 … 13 = 3.5; påhæng ×2; trumfløs ×2; two against two each winner gets the amount once and each loser pays it once, selvmakker against all three. Points are a zero-sum running score from 0. After each runde players see who won what; a score sheet shows every runde and the running totals, with the lookup table (melding × overstik) as the family uses it. The point values are a bord setting with the family table as default. Vip's card factor and banks are added in 07/08; sol values in 09.

**Blocked by:** 03

**Status:** done

- [x] Engine scoring matches every cell of REGLER's lookup table, bet, påhæng and trumfløs doublings, selvmakker.
- [x] Zero sum after every runde; running totals and final standing.
- [x] Score sheet and runde result in the UI; point values editable by the vært before the start.
- [x] Stored runde results replay to the same totals.

## Comments

### Built (branch `esmakker-05`)

- `Esmakker::Scoring` settles a played stik melding with the bord's `Points` (exact Rational arithmetic; whole amounts come back as integers). `RundeResult.played(..., values:)` stores the runde points per seat; `not_played` scores 0. `Esmakker::Game#totals` / `#running_totals` / `#leaders` (highest total).
- Hooks: `RundeResult` has `vip_card` (1–3, ticket 07: vip's factor replaces the påhæng factor; vip itself doubles nothing) and `banks` (ticket 08: ×bank each). Both default to nil/0; a vip result without its card raises.
- State: `score.results[]` carries each runde's `points` and the `totals` after it, `score.leaders` the leading seats. `Game#winner_ids` uses the highest final total at es-makker (`best_seats`).
- UI: the result card shows each seat's stik and points and the totals; a **Stilling** tab (a modal on a narrow screen) with the score sheet (melding, melder + makker, trumf, stik, hjem/bet, points and running total per seat) and REGLER's lookup table built from the bord's point values (`score.ts`, node-tested against every printed cell); the end screen shows the standing and the sheet.
- Tests: `test/models/esmakker/scoring_test.rb` (every cell of the lookup table at gode and halve, bet 1–3 missing, påhæng/trumfløs/vip/bank doublings, selvmakker ×3, zero sum over many cases, custom values), `test/models/esmakker_points_table_test.rb` (vært's values reach the totals; stored runder replay to the same totals; highest total wins), halve points in `gode_halve_test.rb`.

### Valg — for Anders to confirm

- **D1. Two against two, each winner gets the amount from each loser** (so +2× per winner, −2× per loser per runde), as REGLER words it ("hver taber betaler hver vinder").
- **D2. The highest total wins** an es-makker spil (points are won); the glossary's Vinder now says so per game.
- **D3. Vip with a turned joker (trumfløs)** would get both its card factor and trumfløs ×2, since REGLER says trumfløs is "oveni" (ticket 07 to confirm).
- **D4. Amounts are exact**; odd custom values (0,3) are summed without rounding; the UI shows up to two decimals.
- **D5. The lookup table and the notes** are a reference card in the Stilling tab; the sol rows show the (inferred 🔶) values until ticket 09 scores them.

**Changed 2026-10-26 (main session):** D1 was a misreading. Anders: "så vinder både dig og din makker 1 krone fra jeres modspillere" and "vinder fra alle modstandere og deles så med alle vindere". Two against two, each winner gets the amount once and each loser pays it once; a selvmakker settles the amount with each of the three others.
