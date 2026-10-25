import type { SeatIndex } from "~/table/messages"
import type { BiddingEntry, BiddingView, MeldingCode } from "./messages"

/**
 * The meldingsrunde in words, for the es-makker table. Pure: it only words
 * and arranges what the server sent (Esmakker::Round#view_for); which
 * meldinger are legal is the server's.
 */

const SOL_MELDINGER: Record<string, string> = { sol: "sol", ren_sol: "ren sol", bordlaegger: "bordlægger", ren_bordlaegger: "ren bordlægger" }

/** "9", "10 halve", "ren sol". */
export function meldingLabel(code: MeldingCode): string {
  const sol = SOL_MELDINGER[code]
  if (sol) return sol
  const match = /^(\d+)([a-z]*)$/.exec(code)
  if (!match) return code
  return match[2] ? `${match[1]} ${match[2]}` : (match[1] ?? code)
}

export const isSolMelding = (code: MeldingCode) => code in SOL_MELDINGER

/** One button of the ladder: the melding's code, its text in the grid, and its column (1–4). */
export interface LadderCell {
  code: MeldingCode
  text: string
  column: number
}

/**
 * One row of the ladder's grid: a number with its påhæng (`number` is the
 * row's label, shown even when the plain number is no longer offered), or
 * a sol-melding on its own (`number` null).
 */
export interface LadderRow {
  number: string | null
  cells: LadderCell[]
}

/**
 * The meldinger offered, in ladder order, as a grid: one row per number,
 * the plain number in column 1 and its påhæng in columns 2–4, lowest first
 * (the bord's påhæng order, which is given highest first, reversed), and
 * each sol-melding on its own row after the påhæng it follows.
 */
export function ladderRows(codes: MeldingCode[], pahaengOrder: string[]): LadderRow[] {
  const ascending = [...pahaengOrder].reverse()
  const rows: LadderRow[] = []
  for (const code of codes) {
    if (isSolMelding(code)) {
      rows.push({ number: null, cells: [{ code, text: meldingLabel(code), column: 1 }] })
      continue
    }
    const [, number = code, pahaeng = ""] = /^(\d+)([a-z]*)$/.exec(code) ?? []
    const cell = { code, text: pahaeng || number, column: pahaeng ? 2 + ascending.indexOf(pahaeng) : 1 }
    const last = rows[rows.length - 1]
    if (last && last.number === number) last.cells.push(cell)
    else rows.push({ number, cells: [cell] })
  }
  return rows
}

/** What a seat said, in short: "9 vip", "pas", "det kan jeg selv", "går med", "jernhånd". */
export function saidLabel(entry: BiddingEntry): string {
  switch (entry.action) {
    case "bid":
      return entry.melding ? meldingLabel(entry.melding) : ""
    case "pas":
      return "pas"
    case "det_kan_jeg_selv":
      return "det kan jeg selv"
    case "gaa_med":
      return "går med"
    case "jernhaand":
      return "jernhånd"
  }
}

/** One line of the history: "9 vip", "det kan jeg selv (10)". */
export function historyLabel(entry: BiddingEntry): string {
  const said = saidLabel(entry)
  return entry.action === "det_kan_jeg_selv" && entry.melding ? `${said} (${meldingLabel(entry.melding)})` : said
}

/** What each seat said last, for its name tag. */
export function lastSaid(history: BiddingEntry[]): Map<SeatIndex, string> {
  const said = new Map<SeatIndex, string>()
  for (const entry of history) said.set(entry.seat, saidLabel(entry))
  return said
}

/** The players' names by seat, and which seat is you ("du"). */
export interface Names {
  me: SeatIndex
  names: string[]
}

const who = (seat: SeatIndex, { me, names }: Names, capital = true) => (seat === me ? (capital ? "Du" : "du") : (names[seat] ?? `Plads ${seat + 1}`))

/** "Alma", "Alma og Bent", "Alma, Bent og dig". */
function list(seats: SeatIndex[], names: Names): string {
  const words = seats.map((seat) => (seat === names.me ? "dig" : who(seat, names)))
  if (words.length <= 1) return words[0] ?? ""
  return `${words.slice(0, -1).join(", ")} og ${words[words.length - 1]}`
}

/**
 * The middle of the table: the melding standing (or the ending) as the
 * headline, and who holds it, who went with, or what comes next.
 */
export function biddingHeadline(bidding: BiddingView, names: Names): { headline: string; detail: string | null } {
  const { outcome } = bidding
  if (outcome?.kind === "melder") {
    const melding = meldingLabel(outcome.melding)
    const withYou = outcome.went_with.length > 0 ? `Går med: ${list(outcome.went_with, names)}. ` : ""
    const headline = outcome.melder === names.me ? `Du er melder — ${melding}` : `Melder: ${who(outcome.melder, names)} — ${melding}`
    return { headline, detail: `${withYou}Trumf og es kommer.` }
  }
  if (outcome?.kind === "redeal") {
    if (outcome.reason === "jernhaand") {
      const claimer = bidding.history[bidding.history.length - 1]?.seat
      const had = claimer === undefined ? "Jernhånd" : `${who(claimer, names)} har jernhånd`
      return { headline: "Jernhånd", detail: `${had}. Kortene gives om, og ${who(outcome.dealer, names, false)} giver igen.` }
    }
    return { headline: "Alle sagde pas", detail: `Kortene gives om. ${who(outcome.dealer, names)} giver.` }
  }
  if (!bidding.melding || bidding.holder === null) return { headline: "Ingen melding endnu", detail: null }

  const holds = bidding.holder === names.me ? "Du har meldingen" : `${who(bidding.holder, names)} har meldingen`
  const withYou = bidding.went_with.length > 0 ? ` · går med: ${list(bidding.went_with, names)}` : ""
  return { headline: meldingLabel(bidding.melding), detail: `${holds}${withYou}` }
}

/** Whose turn it is and what they may do: "Din tur: meld højere eller sig pas.", "Bent melder …". Null once it is over. */
export function turnText(bidding: BiddingView, names: Names): string | null {
  const seat = bidding.to_act
  if (seat === null || bidding.outcome) return null
  const mine = seat === names.me
  if (bidding.serveret !== null && bidding.melding) {
    const melding = meldingLabel(bidding.melding)
    return mine ? `Din tur: sig "det kan jeg selv" (${melding}) eller pas.` : `${who(seat, names)} kan sige "det kan jeg selv" (${melding}) eller pas.`
  }
  if (!bidding.melding) return mine ? "Din tur: meld eller sig pas." : `${who(seat, names)} melder …`
  return mine ? "Din tur: meld højere eller sig pas." : `${who(seat, names)} skal melde højere eller sige pas.`
}
