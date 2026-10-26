# 07: Gennemspil med botten

**What to build:** After a finished es-makker spil, a player can open any runde and see how the bot (searchbot / Umenneskelig) would have played it: the same deal, the same melding (and the same declarations where they were given), with the bot in a chosen seat or in all seats, trick by trick next to what was actually played, with the bot's expected stik and points at each decision. Anders: "når man har spillet et spil, kan man efterfølgende studere hvordan det optimalt kunne være blevet spillet hvis botten havde valgt — med den samme distribution af hænder og med den melding … så det bliver til træningsmateriale." The runde's log and deal are already stored, so it is a replay from the stored deal with the bot's decisions from the point chosen.

**Blocked by:** 05/06 (a trained net that plays clearly better than Svær, and the net runnable on the server).

**Status:** ready-for-human (decide the view: side by side, or step through with "botten ville have spillet …")

- [ ] Replay any finished runde with the bot in one or all seats, from the deal or from a chosen decision.
- [ ] Shows actual vs bot move per decision, with the bot's expectation.
- [ ] Usable as training material: the player can step through and see where they lost stik/points.
