# 19: Absence and voting

**What to build:** When the player to act has been disconnected or inactive for 60 seconds, the connected humans vote: wait, let a bot take over, or end the spil. A simple majority decides, and a tie means keep waiting. A single remaining human decides alone. A returning player reclaims their seat. A spil ended by vote is saved as abandoned.

**Blocked by:** 10 (Real bots), 18 (Turn timer)

**Status:** ready-for-agent

Spec: `.scratch/v1/spec.md`

- [ ] Disconnect is detected from the channel unsubscribe. Reconnecting cancels a vote that has not yet been decided.
- [ ] Only connected humans vote. The absent player and bots don't.
- [ ] Bot takeover appends to `seat_log` (`{seat, from, to, at_play}`), and the reclaim appends again
- [ ] Ending the spil stores status abandoned with the scores so far
- [ ] Everyone sees the absent player and the vote's progress
- [ ] Table-seam tests cover majority, tie, the single human, takeover, reclaim, abandon and the `seat_log` contents
