import type { SeatIndex } from "~/table/messages"
import type { Names } from "./bidding.ts"
import type { BankWindow } from "./messages"

/**
 * Bank i bordet at vip (REGLER §2.0, ticket 08), in numbers and words for
 * the es-makker table: the bank window's countdown, the doubling of the
 * banks and who banked. Pure: who may bank and when the window closes are
 * the server's (Esmakker::Play, Table#close_bank_window); the client only
 * counts down from when the state arrived, as the turn timer does.
 */

/** Seconds left in the bank window at `now`, counted from when the state arrived (`receivedAt`, ms); null when none is open. */
export function bankSecondsLeft(window: BankWindow | null, receivedAt: number, now: number): number | null {
  if (!window) return null
  return Math.max(0, window.seconds_left - (now - receivedAt) / 1000)
}

/** The countdown as whole seconds: rounded up, so "1" shows until the very end; never below 0. */
export const countdownSeconds = (seconds: number) => Math.max(0, Math.ceil(seconds))

/** How much of the window is left, 0–1, for the bar under the countdown. */
export function countdownFraction(secondsLeft: number, window: BankWindow): number {
  if (window.seconds <= 0) return 0
  return Math.min(1, Math.max(0, secondsLeft / window.seconds))
}

/** The doubling of `banks` banks by the bord's bank factor (standard 2): "×2", "×4"; "" for none. */
export const bankFactor = (banks: number, factor = 2) => (banks > 0 ? `×${formatFactor(factor ** banks)}` : "")

const formatFactor = (value: number) => String(value).replace(".", ",")

/** The bank button: "Bank (×2)" for the first bank, "Bank igen (×4)" for the melder's answer. */
export const bankButtonLabel = (banks: number, factor = 2) => `${banks > 0 ? "Bank igen" : "Bank"} (${bankFactor(banks + 1, factor)})`

const who = (seat: SeatIndex, { me, names }: Names) => (seat === me ? "Du" : (names[seat] ?? `Plads ${seat + 1}`))

/** Who banked, in order: "Bent bankede ×2", "Du bankede igen ×4". */
export function bankLines(banks: SeatIndex[], names: Names, factor = 2): string[] {
  return banks.map((seat, index) => `${who(seat, names)} bankede${index > 0 ? " igen" : ""} ${bankFactor(index + 1, factor)}`)
}

/** The score sheet's note on a runde's banks: "1 bank", "2 bank"; "" for none. */
export const banksNote = (banks: number) => (banks > 0 ? `${banks} bank` : "")
