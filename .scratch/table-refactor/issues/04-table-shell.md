# 04: The table page: a shared shell for what is identical, HjerterfriTablePage and EsmakkerTablePage

**What to build:** Decided with Anders on 2026-10-26 (architecture review, candidate 3): "flyt det du kan ind i en fælles fil … kobl og bind kun det der reelt er det samme. Resten skal ikke bindes." Earn abstractions: similar-looking parts that change for game reasons stay apart.

- **Shared (genuinely identical), into one shared module:** `useAnchors`, `useMediaQuery`, `useHandSize` (copies today); the subscription and message routing (closed, waiting, forladt, rejected → notice, next_path, onRejected → next bord, turn_warning, chat); the panel's frame (tabs, the "‹ Lobby · … · Forbinder…" line, the chat button and sheet with its narrow↔wide behaviour, the leave confirmation).
- **Two pages on top:** rename `TablePage` to `HjerterfriTablePage`; `EsmakkerTablePage` stays its own page.
- **Kept apart (only similar):** the hands, the two timelines, the centre of the felt, the spil/stilling tab bodies and score sheets, the status text.
- **Leaks to remove:** SeatTag's hjerterfri `pass` prop (the game supplies its label extras); `ServerMessage` typing `state` as hjerterfri's state (shared message types carry only the shared envelope; each page has its own state type, no `as unknown as`).
- **Live bugs fixed by sharing:** the es-makker page doesn't show the tur-ur warning; its leave confirmation lacks "en bot overtager din plads"; its chat sheet doesn't turn back into a tab on a wide screen.

**Blocked by:** None (ticket 03 changes the backend; keep the wire format unchanged here).

**Status:** ready-for-agent

- [ ] Shared module with only the identical parts; both pages use it.
- [ ] `HjerterfriTablePage` and `EsmakkerTablePage`; nothing game-specific in the shared module.
- [ ] The two leaks removed; no `as unknown as` casts for state.
- [ ] The three es-makker page bugs fixed.
- [ ] The shell's message routing is a pure function with node tests; `npm test`, `npx tsc`, `bin/rails test` green; visual check of both games at 1400 and 400 px.

## Comments

**Inventory before writing (2026-10-26).** Read side by side, `TablePage.tsx` + `SidePanel.tsx` against `EsmakkerTablePage.tsx`:

- **Identical (shared):** `useAnchors`, `useMediaQuery`, `useHandSize`, `TABS`/`NARROW` (character for character); `OpponentStack` (the same memo); `positionOf` / `seatRect` / `flightSource` (the shared `Trick`'s flight contract, same code in both); the message routing (closed → lobby, waiting → its path, forladt → reload, rejected → notice, next_path remembered, a refused reconnect → the next bord or "Du sidder ikke ved dette bord"); the notice that fades after 3.5 s; the leave form; the panel frame (tabs, "‹ Lobby · … · Forbinder…", chat button and sheet, Stilling button, leave confirmation). The differences inside the routing and frame were the es-makker copy falling behind, not game reasons: `turn_warning` unhandled, the leave text without "en bot overtager din plads", no wide-screen branch back to the chat tab, a confirmation even after the spil, and the notice not cleared by a newer state. These now follow hjerterfri's version.
- **Only similar (kept apart):** the hands (suit-pick + bytte vs. discard/fordækt picking), the timelines (`framesFor` / `esmakkerFrames`), the centre of the felt and its corners, the spil/stilling/regler tab bodies, the score sheets and their modal, the status text (`StatusLine` + `statusText` vs. `status()`), the info line's text, what a rejection resets (the played card vs. the sent choice), what a new runde resets, the overlays (result/game over).
