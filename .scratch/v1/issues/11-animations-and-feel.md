# 11: Animations and game feel

**What to build:** The table feels like a card game. Cards fly from hand to the stik and from the stik to the winner, the hand is sorted, illegal cards are dimmed, and the last stik can be seen.

**Blocked by:** 06 (Practice table end-to-end)

**Status:** ready-for-agent

Spec: `.scratch/v1/spec.md`

- [ ] The hand is sorted by suit and rank
- [ ] Animations use Motion: cards move from hand to the table, and the stik sweeps to its winner after a short pause
- [ ] Bot and opponent plays animate from their seat
- [ ] In the player's own turn, playable cards lift on hover and illegal cards are dimmed
- [ ] A status line explains the turn in plain Danish ("Din tur", "Bekend kulør ♥", "Hjerter er ikke brudt endnu")
- [ ] The last stik is visible in a small card size
- [ ] Everything works by click and touch. Nothing is drag-only.
