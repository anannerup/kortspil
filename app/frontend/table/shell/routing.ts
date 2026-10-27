import type { ServerMessage } from "../messages"
import { REJECTIONS } from "../texts.ts"

export const LOBBY_PATH = "/"

/**
 * What a bord's page does with a message from TableChannel, the same at
 * every game: the chat to the chat, a state to the game's page, and the
 * rest (leaving, the tur-ur's warning, a refused move) handled by the
 * shell. Pure, so it is tested without a browser; useTableShell carries it
 * out.
 */
export type Route<S> =
  | { kind: "chat" }
  | { kind: "state"; state: S }
  /** Leave the page for `to` (the lobby, or the bord the next spil waits at). */
  | { kind: "go"; to: string }
  /** The server decides what this bord's URL shows now (you have forladt the spil). */
  | { kind: "reload" }
  | { kind: "warning"; text: string }
  | { kind: "rejected"; notice: string }

export function routeMessage<S>(message: ServerMessage<S>): Route<S> {
  switch (message.type) {
    case "chat_history":
    case "chat_message":
    case "chat_rejected":
      return { kind: "chat" }
    case "state":
      return { kind: "state", state: message.state }
    case "closed":
      return { kind: "go", to: LOBBY_PATH }
    case "waiting":
      // The bord for the next spil waits in the lobby, at its own URL.
      return { kind: "go", to: message.path }
    case "forladt":
      return { kind: "reload" }
    case "turn_warning":
      return { kind: "warning", text: warningText(message.seconds_left) }
    case "rejected":
      return { kind: "rejected", notice: REJECTIONS[message.reason] ?? "Det kan du ikke her." }
  }
}

/**
 * The subscription was refused: the bord closed when the spil ended, so a
 * reconnect goes on to the new bord (`next_path`); without one you do not
 * sit here.
 */
export function routeRefusal(nextPath: string | null): { kind: "go"; to: string } | { kind: "refused" } {
  return nextPath ? { kind: "go", to: nextPath } : { kind: "refused" }
}

/** The tur-ur's warning on your turn. */
export function warningText(secondsLeft: number): string {
  return `Din tur — ${Math.round(secondsLeft)} sekunder tilbage`
}

/**
 * The leave confirmation: at an øvebord the spil just ends; elsewhere you
 * lose it and a bot takes your seat, or, where no bot takes over
 * (es-makker), the spil ends for everyone.
 */
export function leaveConfirmText(practice: boolean, botTakesOver = true): string {
  if (practice) return "Forlad bordet? Spillet slutter her."
  return botTakesOver
    ? "Forlad bordet? Du taber spillet, og en bot overtager din plads. Du kan ikke vende tilbage til dette spil."
    : "Forlad bordet? Du taber spillet, og det slutter for alle ved bordet."
}
