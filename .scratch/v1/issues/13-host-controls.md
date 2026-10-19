# 13: Host controls

**What to build:** The host can kick a player and add or remove bots before the spil starts. If the host leaves, host passes to the next human. A table with no humans left closes on its own.

**Blocked by:** 12 (Lobby and open tables)

**Status:** ready-for-agent

Spec: `.scratch/v1/spec.md`

- [ ] Kick, add bot and remove bot work only before start, and only for the host
- [ ] When the host leaves, host passes to the next human in seat order
- [ ] A table with no humans closes and disappears from the lobby
- [ ] Table-seam tests cover each of the above
