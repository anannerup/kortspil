import type { ReactNode } from "react"
import { SuitIcon, parseCardCode, type CardCode } from "~/cards"
import type { SeatIndex, TableState } from "./messages"
import { joinNames } from "./texts"

const suitOf = (code: CardCode) => parseCardCode(code).suit

/**
 * The status line under the board, in plain Danish. It only describes what
 * the server sent: whose turn it is (to_act) and which cards it allows
 * (legal_moves). It never decides a rule. When the reason for a limit can
 * be read off the legal moves alone it is named; otherwise the text stays
 * neutral.
 */
export function statusText(state: TableState, nameOf: (seat: SeatIndex | null) => string): ReactNode {
  const { view, seats } = state
  switch (view.phase) {
    case "passing": {
      if (!view.passed_seats.includes(view.seat)) return "Vælg 3 kort at give væk."
      const waiting = seats.filter((seat) => !view.passed_seats.includes(seat.seat)).map((seat) => seat.name)
      return waiting.length > 0 ? `Du har givet dine kort. Venter på ${joinNames(waiting)}…` : "Du har givet dine kort."
    }
    case "choosing_moon":
      return view.to_act === view.seat ? "Du skød månen. Vælg hvordan." : `${nameOf(view.to_act)} skød månen og vælger…`
    case "complete":
      return state.status === "finished" ? "Spillet er slut." : "Runden er slut."
    case "playing": {
      const broken = view.hearts_broken ? " Hjerter er brudt." : ""
      if (view.to_act !== view.seat) return view.to_act === null ? "" : `Venter på ${nameOf(view.to_act)}…${broken}`
      if (view.legal_moves.length === view.hand.length) return `Din tur.${broken}`
      return yourTurn(view.hand, view.legal_moves, view.current_trick[0]?.card ?? null, view.hearts_broken)
    }
  }
}

function yourTurn(hand: CardCode[], legal: CardCode[], led: CardCode | null, heartsBroken: boolean): ReactNode {
  if (led !== null) {
    const ledSuit = suitOf(led)
    if (legal.every((card) => suitOf(card) === ledSuit)) {
      return (
        <>
          Din tur. Bekend kulør <SuitIcon suit={ledSuit} className={`table-status-suit${ledSuit === "D" || ledSuit === "H" ? " hf-red" : ""}`} />
        </>
      )
    }
    return "Din tur. Nogle kort kan ikke spilles nu."
  }

  if (legal.length === 1 && legal[0] === "2C") return "Din tur. Spil klør 2 ud."
  const holdsHearts = hand.some((card) => suitOf(card) === "H")
  const noHeartsAllowed = !legal.some((card) => suitOf(card) === "H")
  if (!heartsBroken && holdsHearts && noHeartsAllowed) return "Din tur. Hjerter er ikke brudt endnu."
  return "Din tur. Nogle kort kan ikke spilles nu."
}
