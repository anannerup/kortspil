# 08: Bank i bordet

**What to build:** Only at vip, within the bank window after trump is named (bord setting, default 8 s, shown as a countdown): the first bank must come from a seat that isn't the melder (the esmakker too if the bord allows it, default yes); after a bank only the melder can bank once more; at most two banks per runde; each bank doubles. The bank option looks the same to all non-melders so the hidden esmakker isn't revealed. The window is timed through the injectable scheduling seam.

**Blocked by:** 07

**Status:** done

- [x] Bank rules exactly as REGLER §2.0, incl. the esmakker setting.
- [x] Countdown; window closes and play starts.
- [x] Each bank ×2 in scoring (gevinst and bet).
- [x] The UI doesn't reveal the esmakker.
- [x] Table tests with fake scheduler/clock.

## Comments

### Built (branch `esmakker-08`)

- Engine: `Esmakker::Play` has a new phase `:banking` between vip's trump and the kitty (`#trump_named` opens it). Nobody is to act (`to_act` nil, so no turn clock and no bot turns). New intents `Bank` (log token `bank`) and `CloseBankWindow` (`bankslut`, logged for the melder's seat; the engine knows no time). `Play#banks` (seats, in order) feeds `RundeResult#banks`, so Scoring's `bank ** banks` applies to gevinst and bet. The second bank closes the window at once. New refusals: `melder_banks_second`, `only_melder_banks_again`, `esmakker_banks_first_not_allowed` (and the bord's `bank_window_closed`).
- Views: `play.bank_window` (open?), `play.banks` (who banked), `choices.bank`. `choices.bank` is true for all three non-melders before the first bank, the esmakker included even when the bord forbids her (`Play#bank_offered?`), so nothing differs between their views; her press is then refused to her alone. After a bank: the melder alone.
- Bord: `Table#bank` (and `TableChannel#bank`); `Table#close_bank_window(game_id:, number:)` run by `BankWindowJob` through `TableScheduler.close_bank_window` (FakeScheduler records `bank_windows`). New column `games.bank_closes_at` (set when the window opens, cleared when it closes; `Game#track_bank_window!`). The job's guard is the runde number plus "still banking", like the bot job's version check: a repeat, a job after the second bank, or one from another runde does nothing. A reconnect schedules the rest of the window again (lost jobs). A bank that arrives after `bank_closes_at` but before the job ran is refused (`bank_window_closed`). The state carries `bank_window: { seconds, seconds_left, closes_at }` while open.
- A bot that took over a seat never banks (`default_intent` is nil in the window); a bot melder waits out the window and then lays the kitty back.
- UI: in the middle of the frame for everyone a countdown ("BANK 7 SEK." with a bar, counted down from when the state arrived, as the turn timer) and the button "Bank (×2)" / "Bank igen (×4)" for those offered it; the text is the same for the three non-melders ("Vil du banke? Hvert bank fordobler."). Who banked shows as a gold "Bank ×4 · bent, alma" pill under the contract in the frame's corner for the rest of the runde; the contract text and the score sheet note "2 bank". Pure wording in `bank.ts` and `play.ts` (node tests). On a phone the middle drops the melding and detail lines during the window (the status line under the felt says them).
- Tests: `test/models/esmakker/bank_test.rb` (engine), `test/models/esmakker_bank_table_test.rb` (bord with FakeScheduler/FakeClock), a channel test, `bank.test.ts`, `play.test.ts`. Ticket 07's vip tests now close the window.

### Valg — for Anders to confirm

- **F1. The window opens before the melder takes the kitty up.** REGLER: "5–10 sekunder efter trumf er meldt". So everyone banks on the same knowledge (trump, the called ace, the turned cards); the melder answers without having seen the kitty, and she does not have to wait between taking it up and laying away. **Changed 2026-10-26 (Anders):** the window opens **after the melder has exchanged with the kitty** (taken up, laid away), before the first stik: whether she took cards is a signal to the others ("hvis melder bytter alle er det et signal om at ikke alle kort var gode"). Phases at vip: `:turning` → `:discarding` → `:banking` → `:playing`. Logs from before this (bank/bankslut before kast) no longer replay (es-makker is not live).
- **F2. One window from trump named.** A first bank does not restart the clock; the melder's answer must come in the time left. The second bank closes it at once. **Changed 2026-10-26 (Anders):** after the first bank the window **starts again**, so the melder has a whole window (the bord's seconds) to bank back (`Game#track_bank_window!(restart:)`). A job from the first window finds its time not out and schedules the rest; the second bank still closes it at once.
- **F3. The esmakker's refused press** (when the bord forbids her to bank first) shows a message to her alone: "Ved dette bord må esmakkeren ikke banke først." The others see nothing; the window stays open for the modspillere.
- **F4. The esmakker banking first (allowed by default)** is public like any bank: everyone sees who banked. That may hint who she is; it is her choice.
- **F5. A selvmakker** (called ace in the kitty, unturned) has no esmakker, so all three may bank first even when the setting is off.
- **F6. A bank after the time ran out** but before the server's job closed the window is refused ("Tiden til at banke er gået."), so a slow network never extends the window.
- **F7. The score sheet shows the number of banks** ("2 bank"), the frame's corner the doubling with the bord's bank factor ("Bank ×4").

