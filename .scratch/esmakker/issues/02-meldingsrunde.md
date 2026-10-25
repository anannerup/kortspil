# 02: The meldingsrunde for stikmeldinger

**What to build:** After the deal the forhånd opens with a melding or pas, and the bidding runs as in REGLER §2.0: one ladder (8, 8 with påhæng in the bord's order, 9 …, 13 with påhæng; sol/bordlægger come in ticket 09), duels where the challenger must pass or bid higher, "det kan jeg selv" (the player who bid first takes over exactly the melding just bid, on any melding), passed players are out, all-pass gives a redeal where the former forhånd loses the forhånd and deals, lowest melding 8, and a jernhånd can be claimed before the bidding for a new deal. Each player is offered only legal meldinger. The bidding ends with a melder and a melding shown to all.

**Blocked by:** 01

**Status:** ready-for-agent

- [ ] Ladder order follows the bord's påhæng order; no suit meldinger, no stærke, nothing below 8.
- [ ] Duels and "det kan jeg selv" exactly as REGLER §2.0, including repeated "det kan jeg selv".
- [ ] All pass → redeal, forhånd lost; jernhånd claim → redeal.
- [ ] Bidding UI offers only legal choices (melding, "det kan jeg selv", pas).
- [ ] Engine tests for every rule; a Table test of a full meldingsrunde.
