import type { CardCode, Suit } from "~/cards"
import type { Names } from "./bidding.ts"
import type { FordaektView, PlayView } from "./messages"
import { SUIT_NAMES } from "./play.ts"

/**
 * Fordækt at the es-makker table, in words and codes: the melder's
 * face-down card that counts as the called ace's suit. Pure: the server
 * says whether she may lay one (choices.fordaekt), which cards may be
 * played, and when the card is turned (Esmakker::Play#fordaekt_view).
 */

/** The code the server sends for the fordækt card while it lies face down in the stik. */
export const FACE_DOWN: CardCode = "fordaekt"

/** Whether a stik's card is shown as its back. */
export const isFaceDown = (code: CardCode) => code === FACE_DOWN

/** The label by the face-down card on the table: "Dit fordækte kort · gælder som ruder", "Bent: fordækt · gælder som ruder". */
export function fordaektLabel(fordaekt: FordaektView, calledAce: Suit | null, names: Names): string {
  const suit = calledAce ? ` · gælder som ${SUIT_NAMES[calledAce]}` : ""
  if (fordaekt.seat === names.me) return `Dit fordækte kort${suit}`
  return `${names.names[fordaekt.seat] ?? `Plads ${fordaekt.seat + 1}`}: fordækt${suit}`
}

/** The face-down card lies on the table, not played yet. */
export const fordaektWaiting = (play: PlayView | null): FordaektView | null => (play?.fordaekt?.waiting ? play.fordaekt : null)

/** The melder's explanation while she may lay a card fordækt (before she leads stik 1). */
export function fordaektOffer(calledAce: Suit): { title: string; detail: string } {
  const suit = SUIT_NAMES[calledAce]
  return {
    title: "Fordækt",
    detail: `Du har ingen ${suit} efter byttet. Du kan lægge ét kort med bagsiden opad; det gælder som ${suit}, og spiller du det ud, skal makkeren lægge esset. Det vendes, når stikket er taget.`,
  }
}
