# 07: Passing

**What to build:** Before each runde, every player picks three cards to pass left, right or across, or holds on the fourth runde. Passing is simultaneous and hidden until everyone has chosen. The cards a player received are highlighted.

**Blocked by:** 06 (Practice table end-to-end)

**Status:** in-progress

Spec: `.scratch/v1/spec.md`

- [ ] The engine supports a passing phase. The direction cycles left, right, across, none by runde number.
- [ ] A pass must be exactly 3 cards from the player's own hand. Nobody sees incoming cards until all passes are in.
- [ ] After the pass, the holder of 2♣ leads
- [ ] Passes are stored in the round's `passes` column, and a rebuild reproduces the post-pass hands
- [ ] The UI shows the direction, lets the player select 3 cards by clicking (no drag), shows "2 af 3 valgt" and highlights the received cards
- [ ] Bots pass 3 random cards
- [ ] Engine tests cover all four directions and the hidden-until-complete rule

## Comments

- Engine part done on branch eng-07-09: `Round` has a passing phase (`Pass` intent, `PassDirection` left/right/across/none by runde, simultaneous and hidden until all four have passed, 2♣ holder after the pass leads), stored as `Passes` (12 codes, `--` for seats not yet passed); UI, bots and DB still to do.
