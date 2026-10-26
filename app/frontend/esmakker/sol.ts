import type { CardCode } from "~/cards"
import type { SeatIndex } from "~/table/messages"
import { exchangedText, meldingLabel, type Names } from "./bidding.ts"
import type { EsmakkerView, RundeResultView, SolPlayView } from "./messages"

/**
 * The sol-meldinger in words, for the es-makker table (REGLER §2.0 "Sol, ren
 * sol og bordlægger"): the kitty going round, who plays the sol-melding,
 * their stik and who is væltet, the bordlægger's open hand, and how it ended. Pure: it only words what
 * the server sent (Esmakker::SolPlay#view_for, SolResult#to_h).
 */

const capital = (text: string) => text.charAt(0).toUpperCase() + text.slice(1)

const who = (seat: SeatIndex, { me, names }: Names, upper = true) => (seat === me ? (upper ? "Du" : "du") : (names[seat] ?? `Plads ${seat + 1}`))

/** "Bent", "Bent og Carla", "Bent, Carla og du". */
function list(seats: SeatIndex[], names: Names, upper = true): string {
  const words = seats.map((seat, index) => who(seat, names, upper && index === 0))
  return words.length <= 1 ? (words[0] ?? "") : `${words.slice(0, -1).join(", ")} og ${words[words.length - 1]}`
}

/** The sol play, when the runde is played on a sol-melding. */
export const solPlay = (view: EsmakkerView): SolPlayView | null => (view.play?.kind === "sol" ? view.play : null)

/** "sol · ingen trumf · es lavest". */
export const solContractText = (melding: string) => `${meldingLabel(melding)} · ingen trumf · es lavest`

/** "ét stik", "ingen stik". */
const allowed = (most: number) => (most === 0 ? "ingen stik" : most === 1 ? "ét stik" : `${most} stik`)

/** "N kort". */
const cards = (count: number) => (count === 1 ? "1 kort" : `${count} kort`)

/**
 * The middle of the table while the kitty goes round: who plays the
 * sol-melding, and whose turn it is to exchange. Null outside that phase.
 */
export function solDeclarationText(view: EsmakkerView, names: Names): { headline: string; detail: string } | null {
  const play = solPlay(view)
  const outcome = view.bidding.outcome
  if (!play || outcome?.kind !== "melder" || view.phase !== "exchanging" || play.exchanging === null) return null
  const melding = meldingLabel(outcome.melding)
  const headline = outcome.melder === names.me ? `Du er melder — ${melding}` : `Melder: ${who(outcome.melder, names)} — ${melding}`
  const actor = play.exchanging
  const size = play.discard_size
  const done = play.exchange_order.flatMap((seat) => {
    const count = play.exchanged[seat]
    return count === null || count === undefined ? [] : [`${exchangedText(seat, count, names)}.`]
  })
  const before = done.length > 0 ? `${done.join(" ")} ` : ""
  if (actor === names.me) {
    const left = size === 3 ? "Katten har 3 kort." : `Der er ${cards(size)} tilbage i katten.`
    return { headline, detail: `${before}${left} Læg op til ${cards(size)} væk, før du ser katten, og tag lige så mange op, eller byt ingen.` }
  }
  return { headline, detail: `${before}${who(actor, names)} bytter med katten (højst ${cards(size)}) …` }
}

/** Who plays the sol-melding: "Bent spiller sol, Carla og du går med". */
export function solPlayersText(play: SolPlayView, melding: string, names: Names): string {
  const [melder, ...others] = play.players
  if (melder === undefined) return ""
  const lead = `${who(melder, names)} spiller ${meldingLabel(melding)}`
  return others.length === 0 ? lead : `${lead}, ${list(others, names, false)} går med`
}

/** The role on a name tag at a sol-melding: "melder", "går med", with "· væltet" once væltet. */
export function solRole(seat: SeatIndex, view: EsmakkerView): string | null {
  const play = solPlay(view)
  const outcome = view.bidding.outcome
  if (!play || outcome?.kind !== "melder" || !play.players.includes(seat)) return null
  const role = seat === outcome.melder ? "melder" : "går med"
  return play.vaeltet.includes(seat) ? `${role} · væltet` : role
}

/** One sol player in the frame's corner: her stik and whether she is væltet. */
export interface SolStatusLine {
  seat: SeatIndex
  name: string
  stik: number
  vaeltet: boolean
}

/** The sol players' status, in the order they took the melding: the melder, then those who went with. */
export function solStatus(play: SolPlayView, names: Names): SolStatusLine[] {
  return play.players.map((seat) => ({ seat, name: who(seat, names), stik: play.tricks_won[seat] ?? 0, vaeltet: play.vaeltet.includes(seat) }))
}

/** The heading over the status: "Højst ét stik", "Ingen stik". */
export const solAllowedText = (most: number) => capital(most === 0 ? "ingen stik" : `højst ${allowed(most)}`)

/** How a sol runde ended, in words: who kept within it, who was væltet, and whether it stopped early. */
export function solResultText(result: RundeResultView, names: Names): { headline: string; detail: string } {
  const sol = result.sol ?? { players: [result.melder], most_stik: 0, vaeltet: [] }
  const melding = capital(meldingLabel(result.melding))
  const klaret = sol.players.filter((seat) => !sol.vaeltet.includes(seat))
  let headline: string
  if (sol.players.length === 1) headline = klaret.length === 1 ? `${melding} klaret` : `${melding} væltet`
  else if (sol.vaeltet.length === 0) headline = `${melding}: alle klarede den`
  else if (klaret.length === 0) headline = `${melding}: alle væltet`
  else headline = `${melding}: ${klaret.length} klaret, ${sol.vaeltet.length} væltet`
  const lines = sol.players.map((seat) => {
    const stik = result.tricks_won[seat] ?? 0
    const took = `${who(seat, names)} tog ${stik} stik`
    return sol.vaeltet.includes(seat) ? `${took} og er væltet.` : `${took} og klarede den.`
  })
  const played = result.tricks_won.reduce((sum, count) => sum + count, 0)
  if (played < 13) lines.push(`Alle sol-spillere var væltet, så runden stoppede efter ${played} stik.`)
  return { headline, detail: lines.join(" ") }
}

/** A sol runde on the score sheet: the players as the melder column, their stik, and how it went. */
export function solOverview(result: RundeResultView, name: (seat: SeatIndex) => string): { melder: string; stik: string; outcome: string } {
  const sol = result.sol ?? { players: [result.melder], most_stik: 0, vaeltet: [] }
  const klaret = sol.players.length - sol.vaeltet.length
  const outcome =
    sol.players.length === 1 ? (klaret === 1 ? "Klaret" : "Væltet") : sol.vaeltet.length === 0 ? "Klaret" : klaret === 0 ? "Væltet" : `${klaret} klaret`
  return {
    melder: sol.players.map(name).join(" + "),
    stik: sol.players.map((seat) => result.tricks_won[seat] ?? 0).join(" · "),
    outcome,
  }
}

/** The most cards the seat laying away may pick: three, or at a sol-melding what is left of the kitty. */
export const discardSize = (view: EsmakkerView) => view.play?.discard_size || 3

/** The button that lays the picked cards away and takes as many up: "Vælg op til 3 kort", "Byt 2 kort". */
export const discardButtonText = (selected: number, size: number) => (selected === 0 ? `Vælg op til ${cards(size)}` : `Byt ${cards(selected)}`)

/**
 * The cards to show face up at another seat: the bordlægger's open hand,
 * once the server lays it open (after the first stik). Null for your own
 * seat (your hand is shown as always) and for every seat while hidden.
 */
export function openHandAt(view: EsmakkerView, seat: SeatIndex): CardCode[] | null {
  const open = solPlay(view)?.open_hand
  return open && open.seat === seat && seat !== view.seat ? open.cards : null
}

/** Danish genitive: "Bents", "Dennis'", "Dine". */
const whose = (seat: SeatIndex, names: Names) => {
  if (seat === names.me) return "Dine"
  const name = who(seat, names)
  return /[sxz]$/i.test(name) ? `${name}'` : `${name}s`
}

/** "Bents kort ligger åbne: 12 kort." */
export const openHandLabel = (seat: SeatIndex, count: number, names: Names) => `${whose(seat, names)} kort ligger åbne: ${cards(count)}.`
