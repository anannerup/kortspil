# 04: The called ace, jokers and fordækt

**What to build:** The esmakker must play the ace the first time its suit is led, and a player void in that suit may not trump the ace. Jokers can be played at any time, win the stik when led and are worthless otherwise; whether a led joker can be beaten by trump follows the bord's setting (default no). A melder with no card in the called ace's suit after the kitty can play fordækt: lay one card face down before the first stik that counts as the ace's suit when led, and is turned once the stik is taken.

**Blocked by:** 03

**Status:** done

- [x] Ace must be played on its suit's first lead; may not be trumped by a void player.
- [x] Joker rules incl. the per-bord trump setting.
- [x] Fordækt: only when void in the ace's suit, only before stik 1; counts as that suit; turned after its stik.
- [x] Engine tests; UI shows jokers, the face-down fordækt card and its reveal.

## Comments

### Built (branch `esmakker-04`)

- `Esmakker::LegalMoves.for(hand:, trick:, trump:, called_ace:)` holds both ace rules; `LegalMoves.rejection` names why a card is refused (`must_play_ace`, `may_not_trump_ace`, `must_follow_suit`). `Trick#winner(trump, joker_trumpable:, called_ace:)` honours the bord's joker setting and the protected ace. `Play` passes the called ace only when there is an esmakker.
- Fordækt: intent `LayFordaekt` (log token `fordaekt-9C`; bord action `Table#lay_fordaekt`, channel `lay_fordaekt`), the laid card a `FordaektCard` (real card + the ace's suit). It is played with the ordinary `play` by its own code. Views: `play.fordaekt` (`card` only for the melder until turned, `waiting`, `turned`); in the open stik the card is `"fordaekt"` for the others; `last_trick` shows its face. `choices.fordaekt` lists the cards she may lay.
- UI: a "Fordækt" box in the panel for the melder (button, then tap the card in the hand), the face-down card by the melder's side of the frame (face, dashed, to her; back to the others), face down in the stik and turned over in place when the stik is taken. Status hints "Din tur: læg ruder-es." and "spil ud, eller læg først et kort fordækt." New refusal texts.
- Tests: `test/models/esmakker/ace_jokers_fordaekt_test.rb` (engine, incl. halve and replay), `test/models/esmakker_ace_fordaekt_table_test.rb` (bord), `app/frontend/esmakker/fordaekt.test.ts`, `play.test.ts`.

### Valg — for Anders to confirm

- **C8. "Esset må ikke stikkes", precisely.** (a) The esmakker must lay the ace in a stik *led* in its suit (also on the fordækt card); the ace is then her only legal card (no joker instead). A stik led with a joker is not "led in the suit", even when the next card makes the suit to follow (C4), so she is not forced there. (b) Once the ace lies in such a stik, a seat void in the suit may not play trump, unless it holds nothing but trump (jokers count as something else). (c) The ace takes that stik whatever trump lies there, also trump played *before* it by a void seat, who could not know the ace was coming (forbidding trump before the ace would make legality depend on where the ace is, which leaks it). So: the called ace's first stik can never be won by trump.
- **C9. The ace rules are the esmakker's.** A selvmakker (ace in the kitty, or all four aces) is not forced to play the ace and her ace is not protected.
- **C10. Jokers when the bord says "kan stikkes med trumf":** a led joker loses to the highest trump in the stik; with no trump in it (or trumfløs) it still wins. C4 kept: after a led joker the first playing card sets the suit to follow (REGLER is silent).
- **C11. Fordækt details.** Only with an esmakker (a selvmakker who laid the ace away has nobody to reach); never a joker ("et (skidt) kort"; a joker is no card of a suit); decided before she leads stik 1 (after the first card it is too late); optional. The card counts as the ace's suit wherever it is played: led, the esmakker lays the ace; if someone else leads the suit, the melder must follow with it; void in another led suit she may discard it. It ranks below every card of the suit. It is turned when its stik is taken. At halve the melder never takes the kitty, so "efter byttet" means her own 13 cards.
