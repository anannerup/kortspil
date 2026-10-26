import type { Suit } from "~/cards"
import { cardLabel, isJoker, type CardCode } from "../cards/cardCode.ts"
import type { SeatIndex } from "~/table/messages"
import { banksNote } from "./bank.ts"
import { exchangedText, meldingLabel, type Names } from "./bidding.ts"
import type { EsmakkerView, RundeResultView, TrumpCode } from "./messages"
import { solContractText, solDeclarationText, solOverview, solPlay, solPlayersText, solResultText, solRole } from "./sol.ts"

export { cardLabel }

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

/** The seat to lay away now, before the kitty is seen (REGLER §2.0: lay away first, then take up). */
function layAwayText(actor: SeatIndex, names: Names): string {
  return actor === names.me
    ? "Læg 0–3 kort væk. Du ser bytterne først, når du har lagt væk, og tager lige så mange op."
    : `${who(actor, names)} lægger kort væk og tager så lige så mange fra bytterne …`
}

/** The melding and how it is played, once named: "8 · trumf: hjerter · ruder-es". */
export function contractText(view: EsmakkerView): string | null {
  const outcome = view.bidding.outcome
  if (outcome?.kind !== "melder" || !view.play) return null
  if (solPlay(view)) return solContractText(outcome.melding)
  const parts = [meldingLabel(outcome.melding)]
  if (view.play.trump) parts.push(view.play.trump === "trumfloes" ? "trumfløs" : `trumf: ${trumpLabel(view.play.trump)}`)
  if (view.play.vip_card) parts.push(vipCardLabel(view.play.vip_card))
  if (view.play.called_ace) parts.push(aceLabel(view.play.called_ace))
  if (view.play.banks.length > 0) parts.push(banksNote(view.play.banks.length))
  return parts.join(" · ")
}

/**
 * The contract in one sentence, as players say it, for the panel: "Bent
 * melder 9 · spar er trumf til klør-es · Carla er esmakker". The esmakker
 * is named only once known; at a sol-melding it is who plays it.
 */
export function contractSentence(view: EsmakkerView, names: Names): string | null {
  const outcome = view.bidding.outcome
  const play = view.play
  if (outcome?.kind !== "melder" || !play) return null
  const sol = solPlay(view)
  if (sol) return solPlayersText(sol, outcome.melding, names)
  const parts = [`${who(outcome.melder, names)} melder ${meldingLabel(outcome.melding)}`]
  const ace = play.called_ace ? aceLabel(play.called_ace) : null
  if (play.trump === "trumfloes") parts.push(ace ? `trumfløs til ${ace}` : "trumfløs")
  else if (play.trump) parts.push(ace ? `${trumpLabel(play.trump)} er trumf til ${ace}` : `${trumpLabel(play.trump)} er trumf`)
  else if (ace) parts.push(`til ${ace}`)
  if (play.vip_card) parts.push(vipCardLabel(play.vip_card))
  if (play.selvmakker) parts.push("selvmakker")
  else if (play.esmakker !== null) parts.push(play.esmakker === names.me ? "du er esmakker" : `${who(play.esmakker, names)} er esmakker`)
  if (typeof play.exchanged === "number") parts.push(exchangedText(declarerOf(view, outcome.melder), play.exchanged, names, false))
  if (play.banks.length > 0) parts.push(banksNote(play.banks.length))
  return parts.join(" · ")
}

/** Who exchanged with the kitty at a stik melding: the melder, at halve the esmakker (or the melder as selvmakker). */
function declarerOf(view: EsmakkerView, melder: SeatIndex): SeatIndex {
  const outcome = view.bidding.outcome
  const esmakker = view.play?.esmakker ?? null
  return outcome?.kind === "melder" && isHalve(outcome.melding) && esmakker !== null ? esmakker : melder
}

/** Whether the melding is a halve: the ace's holder names trump and takes the kitty (REGLER §2.0 "Halve"). */
export const isHalve = (melding: string) => melding.endsWith("halve")

/** Whether the melding is a vip: the melder calls the ace, then turns the kitty's cards for trump (REGLER §2.0 "Vip"). */
export const isVip = (melding: string) => melding.endsWith("vip")

/** "2. kort": which of the kitty's cards, in the order turned. */
export const vipCardLabel = (position: number) => `${position}. kort`

/** The trump a turned kitty card gives: its suit, or trumfløs for a joker. */
export const trumpOfCard = (code: CardCode): TrumpCode => (isJoker(code) ? "trumfloes" : (code.charAt(1) as Suit))

/** The vip melder's button for the next card: the third is trump in any case. */
export function turnCardLabel(turned: number): string {
  const next = turned + 1
  return next >= 3 ? `Vend ${vipCardLabel(next)} (trumf uanset)` : `Vend ${vipCardLabel(next)}`
}

/** The vip melder's button for the card turned last: "Det er trumf: hjerter", "Det er trumf: trumfløs". */
export function acceptTrumpLabel(turned: CardCode[]): string {
  const last = turned.at(-1)
  return last ? `Det er trumf: ${trumpLabel(trumpOfCard(last))}` : "Det er trumf"
}

/** The middle of the table while the melding is declared: what is done now, and by whom. Null outside those phases. */
export function declarationText(view: EsmakkerView, names: Names): { headline: string; detail: string } | null {
  const outcome = view.bidding.outcome
  if (outcome?.kind !== "melder") return null
  if (solPlay(view)) return solDeclarationText(view, names)
  const melder = outcome.melder
  const mine = melder === names.me
  const melding = meldingLabel(outcome.melding)
  const headline = mine ? `Du er melder — ${melding}` : `Melder: ${who(melder, names)} — ${melding}`
  if (isHalve(outcome.melding)) {
    const detail = halveDetail(view, melder, names)
    return detail ? { headline, detail } : null
  }
  if (isVip(outcome.melding)) {
    const detail = vipDetail(view, melder, names)
    return detail ? { headline, detail } : null
  }
  switch (view.phase) {
    case "choosing_trump":
      return { headline, detail: mine ? "Vælg trumf: en farve eller trumfløs." : `${who(melder, names)} vælger trumf …` }
    case "calling_ace":
      return { headline, detail: mine ? "Kald et es, du ikke selv har." : `${who(melder, names)} kalder et es …` }
    case "discarding":
      return { headline, detail: layAwayText(melder, names) }
    default:
      return null
  }
}

/**
 * At halve: the melder calls the ace; then its holder (known to all) or,
 * with the ace in the kitty, the melder as selvmakker names trump, lays
 * cards away and takes as many from the kitty.
 */
function halveDetail(view: EsmakkerView, melder: SeatIndex, names: Names): string | null {
  const ace = view.play?.called_ace
  if (view.phase === "calling_ace") {
    return melder === names.me ? "Sig »jeg er makker til …«: kald et es, du ikke selv har." : `${who(melder, names)} kalder et es: »jeg er makker til …«`
  }
  if (!ace || view.to_act === null || (view.phase !== "choosing_trump" && view.phase !== "discarding")) return null
  const actor = view.to_act
  const mine = actor === names.me
  if (view.phase === "discarding") return layAwayText(actor, names)
  if (view.play?.selvmakker) {
    return mine
      ? `${capital(aceLabel(ace))} ligger i bytterne: du er selvmakker. Vælg trumf: en farve.`
      : `${capital(aceLabel(ace))} ligger i bytterne: ${who(melder, names, false)} er selvmakker og vælger trumf …`
  }
  if (mine) return `Du har ${aceLabel(ace)} og er makker. Vælg trumf: en farve.`
  const partner = melder === names.me ? `${who(actor, names)} er din makker` : `${who(actor, names)} er makker`
  return `${partner} (har ${aceLabel(ace)}) og vælger trumf …`
}

/**
 * At vip: the melder calls the ace, then turns the kitty's cards one by one
 * and takes one as trump (the third in any case); then she lays cards away
 * and takes as many from the kitty. After that the bank window is open
 * (ticket 08; after the exchange since Anders's answers of 26 October
 * 2026), and everybody sees how many she exchanged.
 */
function vipDetail(view: EsmakkerView, melder: SeatIndex, names: Names): string | null {
  const mine = melder === names.me
  const turned = view.play?.turned ?? []
  const last = turned.at(-1)
  switch (view.phase) {
    case "calling_ace":
      return mine ? "Kald et es, du ikke selv har. Så vender du kortene i bytterne for at finde trumf." : `${who(melder, names)} kalder et es og vender så kortene i bytterne …`
    case "turning":
      if (!last) return mine ? "Vend det første kort i bytterne." : `${who(melder, names)} vender det første kort i bytterne …`
      if (!mine) return `${who(melder, names)} har vendt ${cardLabel(last)} (${vipCardLabel(turned.length)}) …`
      return `${capital(vipCardLabel(turned.length))}: ${cardLabel(last)}. Er det trumf, eller vender du ${turned.length === 2 ? "det sidste (trumf uanset)" : "det næste"}?`
    case "banking": {
      // The same words to the three non-melders, so they do not give the esmakker away.
      const exchanged = view.play?.exchanged
      const taken = `${vipTaken(view)}${typeof exchanged === "number" ? `${exchangedText(melder, exchanged, names)}. ` : ""}`
      const first = view.play?.banks[0]
      if (first === undefined) return mine ? `${taken}De andre kan banke nu …` : `${taken}Vil du banke? Hvert bank fordobler.`
      const banked = `${who(first, names)} bankede.`
      return mine ? `${taken}${banked} Du kan banke igen.` : `${taken}${banked} Kun ${who(melder, names, false)} kan banke igen …`
    }
    case "discarding":
      return `${vipTaken(view)}${layAwayText(melder, names)}`
    default:
      return null
  }
}

/** At vip once trump is taken: "Trumf: spar (2. kort). ", "Trumfløs (1. kort). ". */
function vipTaken(view: EsmakkerView): string {
  const trump = view.play?.trump
  const card = view.play?.vip_card
  return trump && card ? `${trump === "trumfloes" ? "Trumfløs" : `Trumf: ${trumpLabel(trump)}`} (${vipCardLabel(card)}). ` : ""
}

/** The title over the ace choice: at halve the melder says "jeg er makker til …". */
export const aceChoiceTitle = (melding: string | null) => (melding && isHalve(melding) ? "Jeg er makker til …" : "Kald et es")

/** The title over the trump choice: at halve a suit, not trumfløs. */
export function trumpChoiceTitle(view: EsmakkerView): string {
  const outcome = view.bidding.outcome
  if (outcome?.kind !== "melder" || !isHalve(outcome.melding)) return "Vælg trumf"
  return "Vælg trumf (en farve)"
}

/** The role shown on a name tag during the play: "melder", "makker" once known, "alene" for a selvmakker. */
export function roleOf(seat: SeatIndex, view: EsmakkerView): string | null {
  const outcome = view.bidding.outcome
  if (outcome?.kind !== "melder" || !view.play) return null
  if (solPlay(view)) return solRole(seat, view)
  if (seat === outcome.melder) return view.play.selvmakker ? "melder · alene" : "melder"
  return seat === view.play.esmakker ? "makker" : null
}

/** "3 stik". */
export const stikLabel = (count: number) => `${count} stik`

/**
 * The status line during the stik: whose turn, and a hint when you must
 * follow suit or may lay a card fordækt first.
 */
export function playTurnText(view: EsmakkerView, names: Names): string | null {
  const play = view.play
  if (!play || view.phase !== "playing") return null
  if (view.to_act === null) return null
  if (view.to_act !== names.me) return `Venter på ${who(view.to_act, names)} …`
  if (play.current_trick.length === 0) return view.choices.fordaekt.length > 0 ? "Din tur: spil ud, eller læg først et kort fordækt." : "Din tur: spil ud."
  const fromHand = play.legal_moves.filter((card) => view.hand.includes(card))
  if (fromHand.length < view.hand.length) return "Din tur: bekend kulør."
  return "Din tur."
}

/** How a runde ended, in words. */
export function resultText(result: RundeResultView, names: Names): { headline: string; detail: string } {
  const melding = meldingLabel(result.melding)
  if (result.kind === "sol") return solResultText(result, names)
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
  /** Vip: "1 bank", "2 bank"; "" without. */
  banks: string
}

export function overviewRows(results: RundeResultView[], names: string[]): OverviewRow[] {
  const name = (seat: SeatIndex | null) => (seat === null ? "" : (names[seat] ?? `Plads ${seat + 1}`))
  return results.map((result, index) => {
    const played = result.kind === "played"
    const sol = result.kind === "sol" ? solOverview(result, name) : null
    return {
      number: index + 1,
      melder: name(result.melder),
      melding: meldingLabel(result.melding),
      trump: result.trump ? `${trumpLabel(result.trump)}${result.vip_card ? ` (${vipCardLabel(result.vip_card)})` : ""}` : "–",
      ace: result.called_ace ? aceLabel(result.called_ace) : "–",
      makker: played ? (result.selvmakker ? "alene" : name(result.esmakker)) : "–",
      stik: played ? String(result.stik) : "–",
      outcome: played ? (result.gik_hjem ? "Hjem" : "Bet") : "–",
      banks: banksNote(result.banks),
      ...sol,
    }
  })
}
