# 19: Leaving and disconnects

**What to build:** A player can leave a spil that is in progress at any time with "Forlad bordet" (confirmed inline: "Forlad bordet? Du taber spillet."). Not coming back within 60 seconds of being frakoblet, or not acting for 60 seconds on one's turn (from ticket 18), counts the same. Either way the player has **forladt** the spil and lost it. A bot takes over the seat (at once on active leave, after the 60 s otherwise), and the spil is played to the end. The player can't return to that spil. The winner is the human with the lowest total; a bot can never win. A player who is frakoblet sees an impossible-to-miss banner at the top of the lobby saying their spil is waiting, with a countdown and a "Tilbage til bordet" button. There is no vote; that replaces the earlier voting design.

**Blocked by:** 12 (Lobby and open tables), 18 (Turn timer and keep-alive)

**Status:** ready-for-agent

Spec: `.scratch/v1/spec.md`. The rules come from the leaving grilling on 2026-10-20; see GLOSSARY.md (Forlade, Frakoblet, Vinder, Afbrudt).

- [ ] "Forlad bordet" works in a multiplayer spil. A bot takes over the seat immediately (it acts at once if it is that seat's turn, including passing). The leaver is recorded as having forladt.
- [ ] The "forladt" event from 18 does the same after 60 s
- [ ] Every takeover is appended to `seat_log` (`{seat, from, to, at_play}`), and the seat is shown as "Bot (overtog fra Anders)". The seat keeps its running totals.
- [ ] A player who has forladt can't rejoin that spil. They can sit down again for the next spil at the bord, if there's a free seat.
- [ ] Result: every player who forlod gets a loss, whatever their points. The vinder is the human (or humans, on a tie) with the lowest total, and a human who ties with a bot still wins. If a bot alone has the lowest total, there's no vinder. Wins count normally.
- [ ] When the last human leaves, the spil is stored as afbrudt (unfinished) and the bord closes. That last leaver still gets a loss.
- [ ] Leaving before the spil starts, or after it's finished, is just standing up, with no loss
- [ ] Øvespil never count in statistics. Leaving a practice bord already works from ticket 08 and stays as it is.
- [ ] When the vært leaves, the next human becomes vært (shared with ticket 13)
- [ ] Lobby banner: a frakoblet player sees "Dit spil er i gang — de venter på dig (0:42)" at the top of the lobby, with a "Tilbage til bordet" button. The "Ved bordet" marker in the nav stays.
- [ ] Table-seam tests cover active leave (with an immediate bot move on their turn and during passing), the 60-s forladt path, no rejoin after forladt, the winner rule (human lowest, a human tied with a bot, a bot lowest means no vinder, human ties), the last human leaving means afbrudt, leaving before start and after finish, and `seat_log` contents. Request test for the banner.
