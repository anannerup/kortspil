# 07: Vip

**What to build:** At vip the melder calls the ace first, then turns the kitty's cards one by one and accepts the first or second as trump or goes on; the third is trump in any case. A turned joker means trumfløs. If the melder stops at the first or second card, the rest of the kitty stays hidden. The melder then takes the kitty up as usual. Points: vip itself gives no doubling; the chosen card gives ×2, ×4 or ×8 (first, second, third).

**Blocked by:** 05

**Status:** done

- [x] Ace before the turns; trump may equal the ace's suit.
- [x] Turning 1–3, joker = trumfløs, unturned cards stay hidden.
- [x] ×2/×4/×8 by card in scoring.
- [x] Engine and Table tests; UI for turning and accepting.

## Comments

### Built (branch `esmakker-07`)

- `Esmakker::Play` plays vip: `:calling_ace` (the melder; she may not call an ace she holds) → `:turning` → `:discarding` → `:playing` → `:complete`. New intents `TurnCard` ("Vend kort", log token `vend`) and `AcceptTrump` ("Det er trumf", `accepter`); the third `vend` names trump by itself. A joker turned is trumfløs. The trump is named in `#trump_named`, which takes the kitty up; ticket 08 puts the bank window there.
- Views: `play.turned` (the cards turned so far, in order, to everyone) and `play.vip_card` (1–3 once taken); unturned cards appear in nobody's view, the melder's included, until she takes the kitty up (then `kitty_cards` to her alone, as usual). `choices.turn_card` / `choices.accept_trump`. New refusal `nothing_turned`.
- Scoring: `RundeResult.played(..., vip_card:)`; ×2/×4/×8 replaces the påhæng factor (05's hook). Vip is no longer "ikke spillet"; the sol-meldinger still are (tests that used vip for "ikke spillet" now use sol).
- Bord: `Table#turn_card`, `#accept_trump`, same `TableChannel` actions. A bot that takes over a seat turns the first card and takes it (C7 style default).
- UI: the panel says "Find trumf i katten" with "Det er trumf: <farve>" and "Vend 2. kort" / "Vend 3. kort (trumf uanset)"; the middle shows the turned cards face up for everyone, the rest as backs, the trump card ringed in gold; the middle text, status line, the contract ("8 vip · trumf: klør · 2. kort · klør-es") and the score sheet's trump column ("klør (2. kort)") name the card. Pure wording in `play.ts` (node tests).
- Tests: `test/models/esmakker/vip_test.rb` (engine), `test/models/esmakker_vip_table_test.rb` (whole vip runder through the bord, and a bot taking over), `play.test.ts`.

### Valg — for Anders to confirm

- **E1. A turned joker does not stop the turning.** REGLER: "Vendes en joker, er det trumfløs" (§2.0) and "Stoppes der ved en joker, spilles der uden trumf" (§2, Whistklubben). I read it as: the joker means trumfløs *if she takes it* (or it is the third); she may also turn on past it. **Confirmed 2026-10-26 (Anders).** The turning goes on until the melder says "det er trumf" or the 3rd card.
- **E2. Vip with a turned joker scores both** its card factor and trumfløs ×2 (05's D3 kept; REGLER says trumfløs is "oveni"). So a joker taken as the third card is ×16. **Confirmed 2026-10-26 (Anders).** Joker as third card: ×8 × 2. Also: **klør** as vip trump doubles once more (×4 × 2 as the 2nd card).
- **E3. The cards she does not turn stay hidden from her too** until she takes the kitty up right after naming trump ("forbliver resten af katten skjult"); then she sees all three and lays three away, as at an ordinary melding. **Changed 2026-10-26 (Anders):** the melder now takes the kitty up right after naming trump and the bank window opens after she has laid away (08 F1).
- **E4. A called ace turned from the kitty** tells everyone the melder is selvmakker at once (everyone saw the ace), so name tags and stik per side show it from then on.
- **E5. Who knows the esmakker at vip**: as at an ordinary melding (03 C5): hidden until the ace is played; vip has no reveal like halve.
- **E6. Fordækt (ticket 04) applies at vip too**, after the kitty, as at an ordinary melding.
