Status: ready-for-agent

# Spec: Es-makker whist — game no. 2

## Problem Statement

Es-makker whist is the card game Anders and his family actually play together; hjerterfri was built first because its rules are simpler. Today kortspil only offers hjerterfri, so when the family wants to play es-makker online they cannot. The game has a demanding bidding round (meldingsrunden) with a family-specific mechanic ("det kan jeg selv"), a hidden partner chosen by calling an ace, a kitty (katten), jokers, sol and bordlægger, banking on vip, and a points table that Anders's father keeps by hand. Doing all of that at a real table takes concentration and bookkeeping; doing it online is impossible without a site that knows their rules.

## Solution

On the home page a player starts a spil by picking the game: two boxes, Hjerterfri and Es-makker. Picking Es-makker opens an es-makker bord, where the vært sets the bord's rules at the table (number of runder, påhæng order, joker rule, bank rules, point values) and invites friends with a puf. When four humans sit at the bord, the vært starts the spil. Kortspil then deals, runs the meldingsrunde, the trump and ace call, the kitty, banking, the play and the scoring exactly by the family's rules, keeps the hidden partner hidden, shows a running score in points, and ends the spil after the chosen number of runder with a final score sheet. The rules are the ones in `docs/rules/REGLER.da.md` §2.0 "Vores bord" (decided with Anders); where §2.0 is silent, the Whistklubben rules in §2 apply.

## User Stories

### Starting and setting up

1. As a player, I want to choose Es-makker on the home page, so that I start an es-makker bord rather than a hjerterfri bord.
2. As a player, I want the game box to be a small, clear choice (two boxes), so that starting a spil is one click.
3. As a vært, I want the bord's game to be fixed once I picked it, so that nobody is surprised by a different game after sitting down.
4. As a vært, I want to set the number of runder (e.g. 10 or 15) at the table, so that we play as long as we usually do.
5. As a vært, I want to set the order of the påhæng (default vip > halve > gode), so that the bord follows our local ranking.
6. As a vært, I want to choose whether jokers can be beaten by trump (default no), so that the bord follows our joker rule.
7. As a vært, I want to choose whether the esmakker may bank first (default yes), so that the bord follows our bank rule.
8. As a vært, I want to set the length of the bank window (default 8 seconds, 5–10), so that banking feels like at the real table.
9. As a vært, I want to adjust the point values (default: the family table), so that we can play for other stakes.
10. As a player who is not the vært, I want to see all of the bord's rules read-only, so that I know what we play before it starts.
11. As a vært, I want to puf my friends to the es-makker bord, so that we can fill the four seats.
12. As a vært, I want "Start spil" to work only when four humans sit at the bord, so that v1 (no es-makker bots) never starts short-handed.
13. As a player, I want the bord to exist only in the lobby until the spil starts, like a hjerterfri bord, so that abandoned set-ups leave nothing behind.

### Dealing and the kitty

14. As a player, I want 55 cards dealt (52 plus three jokers): 13 to each seat and 3 to the kitty, so that the deal matches the real game.
15. As a player, I want the dealer (kortgiver) to move one seat clockwise each runde, and the forhånd to be the seat after the dealer, so that the order is right.
16. As a player holding a jernhånd (no picture cards, no aces, no jokers), I want to claim a new deal before the bidding, so that I am not stuck with a hopeless hand.
17. As a player, I want to see jokers as their own card face, so that I recognise them at once.

### The meldingsrunde

18. As the forhånd, I want to open the bidding with a melding or pas, so that the round starts with me.
19. As the next player, I want to either pass or bid higher on the one ladder of meldinger, so that the bidding follows the fixed order.
20. As a player, I want the ladder to be: 8, 8 with påhæng, 9, 9 with påhæng, sol, 10, 10 with påhæng, ren sol, 11, 11 with påhæng, bordlægger, 12, 12 with påhæng, ren bordlægger, 13, 13 with påhæng — with the påhæng on one number ordered by the bord's påhæng order — so that every melding has exactly one place.
21. As the player who bid first in a duel, I want to say "det kan jeg selv" and take over exactly the melding the other player just bid, so that my serveret gives me first right to the melding.
22. As the challenger after "det kan jeg selv", I want to bid higher again or pass, so that the duel continues until one of us passes.
23. As a player, I want "det kan jeg selv" to work on every melding on the ladder, including sol and bordlægger, so that the serveret always applies.
24. As a player who has not passed, I want to "gå med" on a sol or bordlægger melding, playing the same melding myself, so that several of us can try it.
25. As a player, I want a passed player to be out of the bidding for the rest of the round, so that the bidding ends.
26. As a player, I want a full redeal when everybody passes, with the former forhånd losing the forhånd and dealing, so that the passing rule is as we play it.
27. As a player, I want the lowest melding to be 8, so that 7 is never offered.
28. As a player, I want only legal meldinger offered to me (no suit meldinger, no stærke, no påhæng the bord doesn't use), so that I can't make an invalid bid.

### After the bidding: trump, ace and kitty

29. As the melder of an ordinary melding, I want to name trump (any suit, or trumfløs) and then call an ace I don't hold, so that I choose my partner.
30. As the melder of a gode melding, I want clubs to be trump, so that gode means clubs.
31. As the melder of a halve melding, I want to call an ace ("jeg er makker til …"), after which the ace holder reveals themselves, names trump (a suit other than the called ace's) and takes the kitty, so that halve works as we play it.
32. As the melder of a halve melding whose called ace lies in the kitty, I want to be selvmakker and play alone, so that the rule for a missing partner applies.
33. As the melder of a vip melding, I want to call the ace first, then turn the kitty's cards one by one and accept the first, second or third as trump (the third is trump in any case), so that vip works as we play it.
34. As the melder of a vip melding, I want a turned joker to mean trumfløs, so that the joker rule applies.
35. As the melder of a vip melding who stops at the first or second card, I want the rest of the kitty to stay hidden, so that nobody sees more than they should.
36. As a melder, I want to be forbidden to call an ace I hold myself, so that selvmakker only happens by the "accident" of the ace being in the kitty.
37. As the melder (or, at halve, the esmakker), I want to take the kitty up and discard three cards nobody sees, so that the kitty works as we play it.
38. As the melder of a sol or bordlægger melding, I want to take the kitty first, followed by those who went with, then clockwise from me, so that the kitty order at sol is right.
39. As a melder with no card in the called ace's suit after the kitty, I want to play fordækt — lay one card face down before the first stik that counts as the ace's suit — so that my partner can still be led to.
40. As a player, I want the esmakker to stay hidden from everyone (except at halve) until the ace is played, so that the partnership is a secret, as in the real game.

### Banking

41. As an opponent at a vip melding, I want to bank within the bank window after trump is named, doubling the stake, so that I can punish a bold melding.
42. As the esmakker at a vip melding (when the bord allows it), I want to be able to bank first as well, so that the bank rule follows our bord.
43. As the melder, I want to be able to bank back once somebody has banked, doubling again, so that I can answer.
44. As a player, I want at most two banks per runde, the melder never banking first and only the melder banking second, so that the rule is enforced.
45. As a player, I want a visible countdown during the bank window, so that I know how long I have.
46. As the hidden esmakker, I want the bank option to look the same to everyone, so that it doesn't reveal who I am.

### The play

47. As the melder of a stik melding, I want to lead the first stik myself, so that I can draw trump first.
48. As a player at a sol or bordlægger melding, I want the forhånd to lead, so that the lead is right at sol.
49. As a player, I want to follow suit if I can, so that the basic rule applies.
50. As a player, I want trump to beat other suits, and trumfløs to mean no trump, so that the stik is decided right.
51. As the esmakker, I want to be required to play the ace the first time its suit is led, so that I can't hide my identity by holding the ace back.
52. As a player void in the called ace's suit, I want to be forbidden to trump the ace when it falls, so that "esset må ikke stikkes" holds.
53. As a player, I want a joker to be playable at any time, to win the stik when it is led (it can't be trumped by default), and to be worthless when not led, so that the joker rule applies.
54. As a player, I want the melder's fordækt card, when led, to count as the called ace's suit and to be turned once the stik is taken, so that the fordækt rule works.
55. As a player at sol or bordlægger, I want the ace to be the lowest card and no trump, so that sol is played right.
56. As the opponents of a bordlægger melder, I want the melder's cards laid open after the first stik, so that we can play against them.
57. As players at sol, I want the runde played to the end even when a sol player is "væltet", and stopped only when every sol player is væltet, so that everyone who went with gets their result.
58. As a player, I want a stik melding to go home when melder and esmakker (or the selvmakker alone) take at least the bid number of stik, so that the result is clear.

### Points and the spil

59. As a player, I want points to be a zero-sum running score starting at 0, so that the table always adds up to 0.
60. As a player, I want a melding that goes home to win its stake plus 1 per overstik, times the doublings (påhæng, trumfløs, vip card, banks), from each loser to each winner, so that the scoring matches the family table.
61. As a player, I want a melding that goes bet to lose its stake per missing stik, times the same doublings, so that bet costs what it should.
62. As a selvmakker, I want to win from or lose to all three other players, so that playing alone is settled right.
63. As a player at sol or bordlægger, I want a fixed amount won or lost against each opponent, each player who went with settled separately, so that sol is scored right.
64. As a player, I want to see after each runde who won what and the running totals, so that I can follow the score.
65. As a player, I want a score sheet with every runde's melding, result and points, so that it replaces the paper table.
66. As a player, I want the spil to end after the bord's number of runder with a final standing, so that the evening has an end.
67. As a player, I want every runde stored compactly so it can be replayed later, so that the history is kept (as for hjerterfri).

### At the table, during the spil

68. As a player, I want the table to look and feel like the hjerterfri table (felt, frame, name tags, side panel on the right, card animations), so that kortspil feels like one site.
69. As a player, I want the current melding, trump, called ace and banks shown at all times, so that I don't have to remember them.
70. As a player, I want the turn timer and keep-alive to work as at hjerterfri, so that a slow or lost player doesn't block the table.
71. As a player, I want the table chat during es-makker, so that we can talk while playing.
72. As a player who leaves an es-makker spil in progress, I want to understand the consequence before I confirm, so that I don't leave by accident.
73. As a player on a phone, I want the es-makker table to work in portrait, so that I can play from my phone too.

## Implementation Decisions

- **The rules live in a plain-Ruby engine, `Esmakker`, next to `Hjerterfri`.** No IO, deterministic, injected shuffler/random. Modules (names may sharpen during the build): a 55-card deck with jokers; the deal with the kitty; the ladder of meldinger (numbers, påhæng ordered by the bord's configuration, sol/ren sol/bordlægger/ren bordlægger at their fixed places); the meldingsrunde as a state machine (duels, "det kan jeg selv", gå med, pas, all-pass redeal); the declaration (trump or trumfløs, called ace, gode = clubs, halve reveal, vip kitty turns with joker = trumfløs, the "no own ace" rule); the kitty exchange order; fordækt; the stik play (follow suit, trump, jokers, the ace must be played and may not be trumped, sol: ace lowest and no trump, bordlægger open after the first stik); banking; and the result and points of a runde. A `Round`-like object takes intents and returns a result with the next state, and gives each seat its view, as `Hjerterfri::Round` does.
- **Per-seat views hide what a seat may not know:** other hands, the kitty (except vip's turned cards and the melder's own kitty), the identity of the esmakker until the ace is played (halve excepted), the fordækt card until its stik is taken, and the other cards a bordlægger holds before the first stik.
- **The bord owns its actions** (table-refactor ticket 01, decided with Anders): every action at an es-makker bord is a method on `Table`, which returns an outcome (accepted, or refused with a reason) that controllers only render. The bord dispatches to the game's engine by the bord's game.
- **Rules = TableRules + GameRules.** Es-makker's GameRules: påhæng order (strict, no two påhæng in one tier in v1), joker beatable by trump, esmakker may bank first, bank window length, point values (stakes per number, påhæng factor, trumfløs factor, vip card factors, bank factor, sol values). Es-makker's TableRules add the number of runder. Defaults come from REGLER §2.0.
- **The game is chosen on the home page** and fixed for the bord. Once the spil starts, the stored bord and spil record which game they are.
- **Storage:** an es-makker runde is stored as its deal (55 cards: four hands and the kitty) plus an ordered, compact action log (bids, declarations, kitty discards, fordækt, banks, plays); replaying it through the engine rebuilds the state, as hjerterfri replays its plays. The spil stores its runde results (points per seat) and final standing.
- **Timed steps** (the bank window, the turn clock, the next runde) use the existing injectable scheduling seam, so tests stay deterministic.
- **Points** follow REGLER §2.0 "Point": (stake + overstik) × doublings for a melding that goes home; stake × missing stik × doublings for bet; stakes 8 = 1 … 13 = 3.5 (+0.5 per number); påhæng ×2; trumfløs ×2; vip ×2/×4/×8 by the kitty card (vip itself gives no doubling beyond the card); bank ×2 each; sol 3, ren sol 4, bordlægger 5, ren bordlægger 6 (inferred values, marked as such). Two against two: each loser pays each winner; selvmakker against all three; sol per player who went with.
- **Frontend:** a game-specific table on the same felt/frame/side-panel design and the existing timeline and card-animation building blocks; new pieces for the bidding (ladder with only legal meldinger, "det kan jeg selv", gå med, pas), the declaration (trump, ace, vip turns), the kitty, fordækt, the bank countdown, and the score sheet as a lookup like the family's table.
- **No bots for es-makker in v1.** Four humans; the øvebord stays hjerterfri.

## Testing Decisions

- **Good tests check behaviour through the highest seam**: what a seat sees and may do, and what the score becomes — never internal helper methods.
- **Seam 1: the `Esmakker` engine** (pure Ruby, fast), like the `Hjerterfri::Round` tests: the ladder's order under different påhæng orders; the meldingsrunde (duels, "det kan jeg selv" on every melding, gå med, all-pass redeal and the lost forhånd); declarations per melding type (gode clubs, halve reveal and partner's trump ≠ ace suit, vip turns with joker = trumfløs, no own ace, ace in kitty = selvmakker); the kitty order; fordækt; the play rules (ace must be played, may not be trumped, jokers led win and resist trump by default, sol with ace lowest and no trump, bordlægger open after stik 1, sol played to the end); bank limits; and points against REGLER's table (every cell of the lookup table, bet, doublings, selvmakker, sol per player). A test shows the per-seat view never leaks hidden cards or the hidden esmakker. Seeded random runder replayed from storage give the same state.
- **Seam 2: `Table`** (after table-refactor 01): a whole es-makker spil through the bord's actions with a fake scheduler and clock: setting the bord's rules, starting only with four humans, the order of a runde, the bank window, ending after N runder, leaving.
- **Seam 3: request tests** for the home page game choice and the es-makker bord's settings, plus the existing no-dead-ends route test.
- **Frontend:** `node --test` for pure modules (e.g. the score lookup and the bidding ladder's legal choices). No browser tests in CI; agents verify visually with Playwright screenshots.
- **Prior art:** `test/models/hjerterfri/*` (engine), the TableCommands/Table tests with FakeScheduler/FakeClock, the request tests, `app/frontend/table/*.test.ts`.

## Out of Scope

- Bots for es-makker (a later ticket; the Rust botlab makes them feasible).
- Two påhæng in the same tier (v2).
- Playing for money; points only.
- Statistics and replay viewers.
- Spectators.
- Other player counts than four.
- Klassisk whist.

## Further Notes

- **Source vs decision:** REGLER §2.0 records Anders's decisions (the artefact "Esmakker – regler" and the grillings of 2026-10-25); §2 is the Whistklubben source. Where they differ, §2.0 wins. The sol/bordlægger point values (3/4/5/6) are inferred from their place in the ladder, not stated — they are defaults the vært can change.
- **The ladder order is Anders's:** sol after 9 with påhæng (the source puts sol between 9 and 9+).
- **Open, needs Anders before or during the build:** what happens when a player leaves an es-makker spil in progress, given there are no bots to take over (proposal: the spil is afbrudt for everyone and the leaver loses, scored as forfeited); whether the turn clock and its 60-second forladt apply unchanged to es-makker (bidding may need more time).
- **Depends on** the table-refactor ticket 01 (the bord owns its actions; Rules = TableRules + GameRules) being merged.
- Glossary additions when building: melder, esmakker, modspiller, meldingsrunde, påhæng, serveret, "det kan jeg selv", katten, fordækt, bet, overstik, bank, selvmakker, sol/ren sol/bordlægger.
