import type { Suit } from "~/cards"
import type { SeatIndex } from "~/table/messages"
import { meldingLabel, type Names } from "./bidding.ts"
import type { EsmakkerView, RundeResultView, TrumpCode } from "./messages"

/**
 * The play of a melding in words, for the es-makker table: trump, the
 * called ace, whose turn, the runde result and the spil's overview. Pure:
 * it only words what the server sent (Esmakker::Round#view_for); which
 * cards may be played is the server's.
 */

export const SUIT_NAMES: Record<Suit, string> = { C: "klør", D: "ruder", H: "hjerter", S: "spar" }

/** "hjerter", "trumfløs". */
export const trumpLabel = (trump: TrumpCode) => (trump === "trumfloes" ? "trumfløs" : SUIT_NAMES[trump])

/** "ruder-es". */
export const aceLabel = (suit: Suit) => `${SUIT_NAMES[suit]}-es`

const capital = (text: string) => text.charAt(0).toUpperCase() + text.slice(1)

const who = (seat: SeatIndex, { me, names }: Names, upper = true) => (seat === me ? (upper ? "Du" : "du") : (names[seat] ?? `Plads ${seat + 1}`))

/** "Bent og Alma", "Bent og dig", "Bent alene". */
function side(melder: SeatIndex, esmakker: SeatIndex | null, names: Names): string {
  if (esmakker === null) return `${who(melder, names)} alene`
  const partner = esmakker === names.me ? "dig" : who(esmakker, names)
  return `${who(melder, names)} og ${partner}`
}

/** The melding and how it is played, once named: "8 · trumf: hjerter · ruder-es". */
export function contractText(view: EsmakkerView): string | null {
  const outcome = view.bidding.outcome
  if (outcome?.kind !== "melder" || !view.play) return null
  const parts = [meldingLabel(outcome.melding)]
  if (view.play.trump) parts.push(view.play.trump === "trumfloes" ? "trumfløs" : `trumf: ${trumpLabel(view.play.trump)}`)
  if (view.play.called_ace) parts.push(aceLabel(view.play.called_ace))
  return parts.join(" · ")
}

/** Whether the melding is a halve: the ace's holder names trump and takes the kitty (REGLER §2.0 "Halve"). */
export const isHalve = (melding: string) => melding.endsWith("halve")

/** The middle of the table while the melding is declared: what is done now, and by whom. Null outside those phases. */
export function declarationText(view: EsmakkerView, names: Names): { headline: string; detail: string } | null {
  const outcome = view.bidding.outcome
  if (outcome?.kind !== "melder") return null
  const melder = outcome.melder
  const mine = melder === names.me
  const melding = meldingLabel(outcome.melding)
  const headline = mine ? `Du er melder — ${melding}` : `Melder: ${who(melder, names)} — ${melding}`
  if (isHalve(outcome.melding)) {
    const detail = halveDetail(view, melder, names)
    return detail ? { headline, detail } : null
  }
  switch (view.phase) {
    case "choosing_trump":
      return { headline, detail: mine ? "Vælg trumf: en farve eller trumfløs." : `${who(melder, names)} vælger trumf …` }
    case "calling_ace":
      return { headline, detail: mine ? "Kald et es, du ikke selv har." : `${who(melder, names)} kalder et es …` }
    case "discarding":
      return { headline, detail: mine ? "Du har taget katten. Læg 3 kort væk." : `${who(melder, names)} tager katten og lægger 3 kort væk …` }
    default:
      return null
  }
}

/**
 * At halve: the melder calls the ace; then its holder (known to all) or,
 * with the ace in the kitty, the melder as selvmakker names trump and lays
 * three cards away.
 */
function halveDetail(view: EsmakkerView, melder: SeatIndex, names: Names): string | null {
  const ace = view.play?.called_ace
  if (view.phase === "calling_ace") {
    return melder === names.me ? "Sig »jeg er makker til …«: kald et es, du ikke selv har." : `${who(melder, names)} kalder et es: »jeg er makker til …«`
  }
  if (!ace || view.to_act === null || (view.phase !== "choosing_trump" && view.phase !== "discarding")) return null
  const actor = view.to_act
  const mine = actor === names.me
  if (view.phase === "discarding") return mine ? "Du har taget katten. Læg 3 kort væk." : `${who(actor, names)} tager katten og lægger 3 kort væk …`
  const notAce = `ikke ${SUIT_NAMES[ace]}`
  if (view.play?.selvmakker) {
    return mine
      ? `${capital(aceLabel(ace))} ligger i katten: du er selvmakker. Vælg trumf (${notAce}) eller trumfløs.`
      : `${capital(aceLabel(ace))} ligger i katten: ${who(melder, names, false)} er selvmakker og vælger trumf …`
  }
  if (mine) return `Du har ${aceLabel(ace)} og er makker. Vælg trumf (${notAce}) eller trumfløs.`
  const partner = melder === names.me ? `${who(actor, names)} er din makker` : `${who(actor, names)} er makker`
  return `${partner} (har ${aceLabel(ace)}) og vælger trumf …`
}

/** The title over the ace choice: at halve the melder says "jeg er makker til …". */
export const aceChoiceTitle = (melding: string | null) => (melding && isHalve(melding) ? "Jeg er makker til …" : "Kald et es")

/** The title over the trump choice: at halve not the called ace's suit. */
export function trumpChoiceTitle(view: EsmakkerView): string {
  const outcome = view.bidding.outcome
  const ace = view.play?.called_ace
  if (outcome?.kind !== "melder" || !isHalve(outcome.melding) || !ace) return "Vælg trumf"
  return `Vælg trumf (ikke ${SUIT_NAMES[ace]})`
}

/** The role shown on a name tag during the play: "melder", "makker" once known, "alene" for a selvmakker. */
export function roleOf(seat: SeatIndex, view: EsmakkerView): string | null {
  const outcome = view.bidding.outcome
  if (outcome?.kind !== "melder" || !view.play) return null
  if (seat === outcome.melder) return view.play.selvmakker ? "melder · alene" : "melder"
  return seat === view.play.esmakker ? "makker" : null
}

/** "3 stik". */
export const stikLabel = (count: number) => `${count} stik`

/**
 * The status line during the stik: whose turn, and a hint when you must
 * follow suit, must lay the called ace, or may lay a card fordækt first.
 */
export function playTurnText(view: EsmakkerView, names: Names): string | null {
  const play = view.play
  if (!play || view.phase !== "playing") return null
  if (view.to_act === null) return null
  if (view.to_act !== names.me) return `Venter på ${who(view.to_act, names)} …`
  if (play.current_trick.length === 0) return view.choices.fordaekt.length > 0 ? "Din tur: spil ud, eller læg først et kort fordækt." : "Din tur: spil ud."
  if (play.called_ace && play.legal_moves.length === 1 && play.legal_moves[0] === `A${play.called_ace}`) return `Din tur: læg ${aceLabel(play.called_ace)}.`
  const fromHand = play.legal_moves.filter((card) => view.hand.includes(card))
  if (fromHand.length < view.hand.length) return "Din tur: bekend kulør."
  return "Din tur."
}

/** How a runde ended, in words. */
export function resultText(result: RundeResultView, names: Names): { headline: string; detail: string } {
  const melding = meldingLabel(result.melding)
  if (result.kind === "not_played") {
    return {
      headline: `${capital(melding)} spilles ikke endnu`,
      detail: `${who(result.melder, names)} vandt meldingen. Den slags melding kommer i en senere version; runden tæller uden point.`,
    }
  }
  const number = Number.parseInt(result.melding, 10)
  const players = side(result.melder, result.esmakker, names)
  if (result.gik_hjem) {
    const over = result.stik - number
    return { headline: `${melding} gik hjem`, detail: `${players} tog ${result.stik} stik${over > 0 ? ` (${over} overstik)` : ""}.` }
  }
  return { headline: `${melding} gik bet`, detail: `${players} tog ${result.stik} stik — ${number - result.stik} for lidt.` }
}

/** One line of the spil's overview: every completed runde's melding, how it was played, and how it went. */
export interface OverviewRow {
  number: number
  melder: string
  melding: string
  trump: string
  ace: string
  makker: string
  stik: string
  outcome: string
}

export function overviewRows(results: RundeResultView[], names: string[]): OverviewRow[] {
  const name = (seat: SeatIndex | null) => (seat === null ? "" : (names[seat] ?? `Plads ${seat + 1}`))
  return results.map((result, index) => {
    const played = result.kind === "played"
    return {
      number: index + 1,
      melder: name(result.melder),
      melding: meldingLabel(result.melding),
      trump: result.trump ? trumpLabel(result.trump) : "–",
      ace: result.called_ace ? aceLabel(result.called_ace) : "–",
      makker: played ? (result.selvmakker ? "alene" : name(result.esmakker)) : "–",
      stik: played ? String(result.stik) : "–",
      outcome: played ? (result.gik_hjem ? "Hjem" : "Bet") : "Ikke spillet",
    }
  })
}
