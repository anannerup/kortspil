# 12: Lobby and open tables

**What to build:** Approved users see a live lobby of open tables. They can create a table, choose a seat, sit and stand up, and the host starts the spil when all four seats are filled with humans. Every table has its own URL. A player can sit at only one table at a time. The admin sees the active tables.

**Blocked by:** 06 (Practice table end-to-end)

**Status:** ready-for-agent

Spec: `.scratch/v1/spec.md`

- [ ] The lobby lists open tables with host, seats and status, and updates live over Action Cable
- [ ] Create table, choose seat, sit and leave all work before start
- [ ] The host can start only when 4 seats are filled. The practice table from 06 still works.
- [ ] Every table has a stable URL that opens the table view
- [ ] Sitting at a second table is refused with a clear message
- [ ] Multiple humans play a spil together, each receiving only their own hand
- [ ] The admin page lists the active tables
- [ ] Table-seam tests cover seating, the one-table rule and the start condition with several humans

## Comments

- 2026-10-20, Anders: a player can leave a spil with other humans at any time, and leaving before the end means **they lose the spil**. The confirmation says "Forlad bordet? Du taber spillet." The leaver is recorded as forfeiting, so stats count it as a loss. Confirmed by Anders: by default a bot takes over the seat so the others can finish, and the result marks the leaver as the loser regardless of points. The word "by default" leaves room for a table option later.
- [ ] Leaving mid-spil asks for confirmation, records the leaver as forfeiting (a loss), hands their seat to a bot, and lets the others continue
