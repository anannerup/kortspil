# 04: Es-makker-motoren i Python

**What to build:** The es-makker engine (meldingsrunde, declarations, kitty, fordækt, play, sol-meldinger, scoring, our bord's rules) in Python under tools/, fast enough for self-play, kept equal to the Ruby engine by a parity check on recorded action logs (like botlab's parity_record.rb). Includes the first bot (01) and an observation per seat with only what that seat may know.

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] Parity: thousands of seeded spil give identical states and points in Ruby and Python.
- [ ] Observation never leaks hidden cards or the hidden makker.
