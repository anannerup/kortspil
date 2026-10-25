# 04: The called ace, jokers and fordækt

**What to build:** The esmakker must play the ace the first time its suit is led, and a player void in that suit may not trump the ace. Jokers can be played at any time, win the stik when led and are worthless otherwise; whether a led joker can be beaten by trump follows the bord's setting (default no). A melder with no card in the called ace's suit after the kitty can play fordækt: lay one card face down before the first stik that counts as the ace's suit when led, and is turned once the stik is taken.

**Blocked by:** 03

**Status:** ready-for-agent

- [ ] Ace must be played on its suit's first lead; may not be trumped by a void player.
- [ ] Joker rules incl. the per-bord trump setting.
- [ ] Fordækt: only when void in the ace's suit, only before stik 1; counts as that suit; turned after its stik.
- [ ] Engine tests; UI shows jokers, the face-down fordækt card and its reveal.
