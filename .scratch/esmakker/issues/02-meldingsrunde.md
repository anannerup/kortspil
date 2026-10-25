# 02: The meldingsrunde for stikmeldinger

**What to build:** After the deal the forhånd opens with a melding or pas, and the bidding runs as in REGLER §2.0: one ladder (8, 8 with påhæng in the bord's order, 9 …, 13 with påhæng; sol/bordlægger come in ticket 09), duels where the challenger must pass or bid higher, "det kan jeg selv" (the player who bid first takes over exactly the melding just bid, on any melding), passed players are out, all-pass gives a redeal where the former forhånd loses the forhånd and deals, lowest melding 8, and a jernhånd can be claimed before the bidding for a new deal. Each player is offered only legal meldinger. The bidding ends with a melder and a melding shown to all.

**Blocked by:** 01

**Status:** ready-for-agent

- [ ] Ladder order follows the bord's påhæng order; no suit meldinger, no stærke, nothing below 8.
- [ ] Duels and "det kan jeg selv" exactly as REGLER §2.0, including repeated "det kan jeg selv".
- [ ] All pass → redeal, forhånd lost; jernhånd claim → redeal.
- [ ] Bidding UI offers only legal choices (melding, "det kan jeg selv", pas).
- [ ] Engine tests for every rule; a Table test of a full meldingsrunde.

## Comments

### Antagelser (bidding engine, `Esmakker::Bidding`) — for Anders to confirm

Where §2.0 (and §2 behind it) leaves the order of turns open, the engine reads it like this. The same labels (A1–A8) are in the comments in `app/models/esmakker/bidding.rb`.

- **A1.** When the challenger bids higher, the player who held the melding (serveretten) can only say "det kan jeg selv" or pas (or gå med if it is a sol-melding, see A5). She can't bid even higher herself.
- **A2.** After "det kan jeg selv" the turn goes straight back to the challenger, who bids higher or says pas ("Derefter kan udfordreren melde højere igen … eller sige pas").
- **A3.** After a pas (from the challenger, or from the holder who then loses the melding to the challenger) the new challenger is the **next seat clockwise after the challenger** who hasn't passed or gone with. The turn only moves forward, so each seat gets to challenge once. §2.6's "the melding goes back round to the player after the dealer" (Whistklubben) is **not** used; §2.0's duels win.
- **A4.** A pas is always final, also in the opening: if the forhånd says pas and seat 2 bids 8, the forhånd can't come back in.
- **A5.** Gå med: only on the four sol-melding meldinger (not vip, which §2.7/§2.9 allow at Whistklubben), and only **on your turn**, instead of pas or bidding higher. The holder may also gå med on a sol-melding the challenger just bid, instead of "det kan jeg selv"; the challenger then keeps it. Going with means you're out of the bidding. If the sol-melding is then bid over, those who went with are simply out and play nothing (§2.7 example 1). If the holder takes over the sol-melding with "det kan jeg selv", earlier gå med on that same sol-melding still count, and the challenger may go with as well.
- **A6.** Jernhånd: any seat holding one may claim it **out of turn** at any time before the first bid (passes before that don't matter). The redeal is dealt by the **same kortgiver**, and the forhånd stays with the same seat (§2.4/§2.0 only say "new deal"). An unclaimed jernhånd is just played.
- **A7.** All four pass: the former forhånd deals the redeal (`outcome.dealer`), so the new forhånd is the seat after her. Wiring this into the dealer rotation is up to the runde.
- **A8.** Ladder: sol/ren sol/bordlægger/ren bordlægger come after the påhæng on 9/10/11/12 (Anders's order, §2.0's closing note, tickets 09/10). The paragraph "Én meldstige" in §2.0 still says "som i 2.8 … under samme tal med påhæng", which contradicts this and should probably be fixed in REGLER.

**Anders, 26. oktober 2026:** A1–A7 bekræftet. Til A6: ved jernhånd går runden om, og den, der havde forhånd, beholder den.
