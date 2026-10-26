# 12: Es-makker bots

**What to build:** Bots that play es-makker, at the levels Let, Mellem and Svær, as players in their seats (like hjerterfri's bots: a bot acts for itself through the bord's ordinary actions). They bid in the meldingsrunde (incl. "det kan jeg selv", gå med on sol-meldinger, pas, jernhånd), declare (trump/trumfløs, called ace, vip turns, halve as partner), take the kitty and discard, play fordækt, bank, and play stik and sol-meldinger. They make an øvebord for es-makker possible, fill empty seats at an es-makker bord, and take over the seat of a player who forlader (ticket 11). Developed and tuned in the Rust botlab (tools/botlab) and ported to Ruby with a parity check, measured with same-hand duplicate play, as for hjerterfri. The strategy is decided with Anders (grill first, as ticket 20 did for hjerterfri).

**Blocked by:** 03 (the play), and for the full set 04–10.

**Status:** grilled 26 October 2026; split into .scratch/esmakker-bots/issues (strategy in docs/bots/esmakker-strategy.md)

- [ ] Strategy grilled with Anders and written to docs/bots/esmakker-strategy.md.
- [ ] Engine port to the botlab, levels, tournament and parity.
- [ ] Bots seated at an es-makker bord; es-makker øvebord; takeover on forlade.
