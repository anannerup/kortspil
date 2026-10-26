# 04: The table page: a shared shell for what is identical, HjerterfriTablePage and EsmakkerTablePage

**What to build:** Decided with Anders on 2026-10-26 (architecture review, candidate 3): "flyt det du kan ind i en fælles fil … kobl og bind kun det der reelt er det samme. Resten skal ikke bindes." Earn abstractions: similar-looking parts that change for game reasons stay apart.

- **Shared (genuinely identical), into one shared module:** `useAnchors`, `useMediaQuery`, `useHandSize` (copies today); the subscription and message routing (closed, waiting, forladt, rejected → notice, next_path, onRejected → next bord, turn_warning, chat); the panel's frame (tabs, the "‹ Lobby · … · Forbinder…" line, the chat button and sheet with its narrow↔wide behaviour, the leave confirmation).
- **Two pages on top:** rename `TablePage` to `HjerterfriTablePage`; `EsmakkerTablePage` stays its own page.
- **Kept apart (only similar):** the hands, the two timelines, the centre of the felt, the spil/stilling tab bodies and score sheets, the status text.
- **Leaks to remove:** SeatTag's hjerterfri `pass` prop (the game supplies its label extras); `ServerMessage` typing `state` as hjerterfri's state (shared message types carry only the shared envelope; each page has its own state type, no `as unknown as`).
- **Live bugs fixed by sharing:** the es-makker page doesn't show the tur-ur warning; its leave confirmation lacks "en bot overtager din plads"; its chat sheet doesn't turn back into a tab on a wide screen.

**Blocked by:** None (ticket 03 changes the backend; keep the wire format unchanged here).

**Status:** done

- [x] Shared module with only the identical parts; both pages use it.
- [x] `HjerterfriTablePage` and `EsmakkerTablePage`; nothing game-specific in the shared module.
- [x] The two leaks removed; no `as unknown as` casts for state.
- [x] The three es-makker page bugs fixed.
- [x] The shell's message routing is a pure function with node tests; `npm test`, `npx tsc`, `bin/rails test` green; visual check of both games at 1400 and 400 px.

## Comments

**Inventory before writing (2026-10-26).** Read side by side, `TablePage.tsx` + `SidePanel.tsx` against `EsmakkerTablePage.tsx`:

- **Identical (shared):** `useAnchors`, `useMediaQuery`, `useHandSize`, `TABS`/`NARROW` (character for character); `OpponentStack` (the same memo); `positionOf` / `seatRect` / `flightSource` (the shared `Trick`'s flight contract, same code in both); the message routing (closed → lobby, waiting → its path, forladt → reload, rejected → notice, next_path remembered, a refused reconnect → the next bord or "Du sidder ikke ved dette bord"); the notice that fades after 3.5 s; the leave form; the panel frame (tabs, "‹ Lobby · … · Forbinder…", chat button and sheet, Stilling button, leave confirmation). The differences inside the routing and frame were the es-makker copy falling behind, not game reasons: `turn_warning` unhandled, the leave text without "en bot overtager din plads", no wide-screen branch back to the chat tab, a confirmation even after the spil, and the notice not cleared by a newer state. These now follow hjerterfri's version.
- **Only similar (kept apart):** the hands (suit-pick + bytte vs. discard/fordækt picking), the timelines (`framesFor` / `esmakkerFrames`), the centre of the felt and its corners, the spil/stilling/regler tab bodies, the score sheets and their modal, the status text (`StatusLine` + `statusText` vs. `status()`), the info line's text, what a rejection resets (the played card vs. the sent choice), what a new runde resets, the overlays (result/game over).

**Done (2026-10-26).** The shell is `app/frontend/table/shell/`: `routing.ts` (`routeMessage`, `routeRefusal`, `warningText`, `leaveConfirmText`; pure, node tests in `routing.test.ts`), `useTableShell` (subscription, notice, warning, connection, `next_path`, leave form ref), `TablePanel` (the frame; the game passes the info line, the spil/stilling/regler bodies, the status and its primary button), `Felt.tsx` (`OpponentStack`, `TableToasts`, `LeaveForm`) and `hooks.ts` (`useAnchors`, `useTrickAnchors`, `useMediaQuery`, `useHandSize`). `TablePage` is `HjerterfriTablePage`; hjerterfri's `SidePanel` and `EsmakkerSidePanel` fill `TablePanel`. Leaks: `ServerMessage<S>` carries the game's state as a type parameter (`subscribeToTable<S>`), hjerterfri's state is `HjerterfriTableState`, the timer is `TurnTimer`, SeatTag's `pass` is a game-supplied `marker` class, `StatusLine` takes only the fields it reads. Wire format unchanged. Small unifications toward hjerterfri's version (the es-makker copy had fallen behind): a newer state clears the notice, the warning clears on a newer version (at arrival, not when the timeline shows it), and leaving after the spil needs no confirmation. Not done, on purpose: es-makker's status line has no "Venter på … 0:12" countdown (`StatusLine`); that would be a new feature there, not a shared fix.

Checked at 1400×900 and 400 px: hjerterfri øvebord in the bytte and in play (the bytte markers on the tags), es-makker bord with alma, bent, carla, dennis: "Din tur — 30 sekunder tilbage" on bent's page, the leave text with "en bot overtager din plads", the chat sheet at 400 px turning back into the Chat tab at 1400.
