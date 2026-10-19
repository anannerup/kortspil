# 11: Animations and game feel

**What to build:** The table feels like a card game. Cards fly from hand to the stik and from the stik to the winner, the hand is sorted, illegal cards are dimmed, and the last stik can be seen.

**Blocked by:** 06 (Practice table end-to-end)

**Status:** done

Spec: `.scratch/v1/spec.md`

- [x] The hand is sorted by suit and rank
- [x] Animations use Motion: cards move from hand to the table, and the stik sweeps to its winner after a short pause
- [x] Bot and opponent plays animate from their seat
- [x] In the player's own turn, playable cards lift on hover and illegal cards are dimmed
- [x] A status line explains the turn in plain Danish ("Din tur", "Bekend kulør ♥", "Hjerter er ikke brudt endnu")
- [x] The last stik is visible in a small card size
- [x] Everything works by click and touch. Nothing is drag-only.

## Comments

- Done on branch t11-animations (frontend only). The server already sends the hand sorted (`Round#in_display_order`: klør, ruder, spar, hjerter; low to high); the client keeps that order. Motion 12.43.0: your card flies from where it sat in the hand, opponents' cards from their card backs; a completed stik rests briefly and sweeps to `last_trick_winner`; plays of the next stik wait for the sweep (it is cut short when they arrive). The hand slides closed and fades in on a new deal. All with transform/opacity; the board no longer clips so flights can cross into it. `prefers-reduced-motion`: no flights, no sweep, instant updates. "Sidste stik" is shown in small cards in the board's top-left corner (winner's card ringed), replacing the faded stik in the middle. The status line reads only `to_act`, `legal_moves`, `current_trick` and `hearts_broken` ("Din tur.", "Bekend kulør ♥", "Hjerter er ikke brudt endnu.", "Spil klør 2 ud.", otherwise the neutral "Nogle kort kan ikke spilles nu."). Not checked in a browser by the agent.
