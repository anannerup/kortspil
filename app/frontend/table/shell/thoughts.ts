import type { CardCode } from "../../cards/cardCode.ts"
import type { BotThought, SeatIndex, VisKort } from "../messages"

/**
 * "Vis kort" (Game::VisKort), the same at every game: the bots' hands face
 * up at their seats, and a log of the bots' thoughts, one line per
 * decision. Each game words its own thoughts. Pure, so it is tested
 * without a browser.
 */

/** A bot's thought in the log, with its seat. */
export interface LoggedThought<T> {
  seat: SeatIndex
  thought: BotThought<T>
}

/** How many lines the log keeps. */
export const LOG_SIZE = 40

/** The bot's hand to show face up at its seat, when "Vis kort" is on; otherwise null. */
export function revealedHand<T>(visKort: VisKort<T> | null | undefined, seat: SeatIndex): CardCode[] | null {
  if (!visKort?.on) return null
  return visKort.bots.find((bot) => bot.seat === seat)?.hand ?? null
}

/**
 * The log after a state: the thoughts it carries that are new (a bot's
 * thought is new until one with its seat and version is logged), newest
 * first. Only this runde's (`roundNumber`, the state's round row): a new
 * runde starts an empty log, and a thought left from the runde before is
 * not logged. Switched off, the log empties.
 */
export function logThoughts<T>(log: LoggedThought<T>[], visKort: VisKort<T> | null | undefined, roundNumber: number): LoggedThought<T>[] {
  if (!visKort?.on) return log.length === 0 ? log : []
  const current = log.filter((entry) => entry.thought.round_number === roundNumber)
  const fresh = visKort.bots
    .flatMap((bot) => (bot.thought && bot.thought.round_number === roundNumber ? [{ seat: bot.seat, thought: bot.thought }] : []))
    .filter((entry) => !current.some((logged) => logged.seat === entry.seat && logged.thought.version === entry.thought.version))
    .sort((a, b) => b.thought.version - a.thought.version)
  if (fresh.length === 0 && current.length === log.length) return log
  return [...fresh, ...current].slice(0, LOG_SIZE)
}
