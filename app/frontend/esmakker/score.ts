import type { SeatIndex } from "~/table/messages"
import type { EsmakkerPoints, RundeResultView, ScoreRow, StakeNumber } from "./messages"
import { overviewRows, type OverviewRow } from "./play.ts"
import { amount } from "./rules.ts"

/**
 * The score in words and tables, for the es-makker table: the runde points
 * the server sent (Esmakker::Scoring) per seat with the running totals,
 * the final standing, and REGLER §2.0's lookup table ("Opslagstabel") for
 * the family's bookkeeping, built from the bord's point values. The lookup
 * table is a reference card only; what a runde scores is the server's.
 */

/** "+2", "−1,5", "0": a runde's points, signed. */
export function signedPoints(value: number): string {
  const rounded = round(value)
  if (rounded === 0) return "0"
  return `${rounded > 0 ? "+" : "−"}${amount(Math.abs(rounded))}`
}

/** "4", "−1,5": a total. */
export const totalPoints = (value: number) => {
  const rounded = round(value)
  return rounded < 0 ? `−${amount(-rounded)}` : amount(rounded)
}

const round = (value: number) => Math.round(value * 100) / 100

/** One row of the score sheet: the runde as in the overview, its points per seat and the totals after it. */
export interface SheetRow extends OverviewRow {
  points: number[]
  totals: number[]
}

export function sheetRows(results: ScoreRow[], names: string[]): SheetRow[] {
  const rows = overviewRows(results, names)
  return rows.map((row, index) => ({ ...row, points: results[index]?.points ?? [], totals: results[index]?.totals ?? [] }))
}

/** One line of the final standing: highest total first; ties share a place. */
export interface StandingLine {
  seat: SeatIndex
  name: string
  total: number
  place: number
}

export function standing(totals: number[], names: string[]): StandingLine[] {
  const lines = totals.map((total, seat) => ({ seat: seat as SeatIndex, name: names[seat] ?? `Plads ${seat + 1}`, total }))
  lines.sort((a, b) => b.total - a.total || a.seat - b.seat)
  return lines.map((line) => ({ ...line, place: 1 + lines.filter((other) => other.total > line.total).length }))
}

/** Who won what in one runde, for the result card: "Bent +4", in seat order. */
export function runderPointsLine(result: RundeResultView, names: string[]): { seat: SeatIndex; name: string; points: string }[] {
  return result.points.map((points, seat) => ({ seat: seat as SeatIndex, name: names[seat] ?? `Plads ${seat + 1}`, points: signedPoints(points) }))
}

/** The overstik columns of the lookup table: præcis, +1 … +5. */
export const LOOKUP_COLUMNS = ["præcis", "+1", "+2", "+3", "+4", "+5"] as const

/** One row of the lookup table: a number ("8"), the number with påhæng ("8p"), or a sol-melding with its fixed amount. */
export interface LookupRow {
  label: string
  kind: "number" | "pahaeng" | "sol"
  /** The amount per loser and winner for præcis, +1 … +5; null where the overstik cannot be taken (or at a sol-melding). */
  cells: (number | null)[]
}

const SOL_AFTER: Partial<Record<StakeNumber, { key: "sol" | "ren_sol" | "bordlaegger" | "ren_bordlaegger"; label: string }>> = {
  "9": { key: "sol", label: "Sol" },
  "10": { key: "ren_sol", label: "Ren sol" },
  "11": { key: "bordlaegger", label: "Bordlægger" },
  "12": { key: "ren_bordlaegger", label: "Ren bordlægger" },
}

const NUMBERS: StakeNumber[] = ["8", "9", "10", "11", "12", "13"]
const MOST_STIK = 13

/**
 * REGLER §2.0's lookup table from the bord's point values: per melding
 * that goes home, (stake + overstik) × påhæng ("p") per loser and winner,
 * in the ladder's order with the sol-meldinger after their påhæng.
 */
export function lookupTable(points: EsmakkerPoints): LookupRow[] {
  const rows: LookupRow[] = []
  for (const number of NUMBERS) {
    const stake = points.stakes[number]
    const cells = (factor: number) =>
      LOOKUP_COLUMNS.map((_, over) => (Number(number) + over > MOST_STIK ? null : round((stake + over) * factor)))
    rows.push({ label: number, kind: "number", cells: cells(1) })
    rows.push({ label: `${number}p`, kind: "pahaeng", cells: cells(points.pahaeng) })
    const sol = SOL_AFTER[number]
    if (sol) rows.push({ label: sol.label, kind: "sol", cells: LOOKUP_COLUMNS.map((_, over) => (over === 0 ? points[sol.key] : null)) })
  }
  return rows
}

/** The notes under the lookup table: what "p" is, the other doublings, and bet. */
export function lookupNotes(points: EsmakkerPoints): string[] {
  const factor = (value: number) => `×${amount(value)}`
  return [
    `p = med påhæng (gode, halve) ${factor(points.pahaeng)}. Vip i stedet efter kortene fra bytterne: 1. kort ${factor(points.vip_first)}, 2. kort ${factor(points.vip_second)}, 3. kort ${factor(points.vip_third)}.`,
    `Oveni: trumfløs ${factor(points.trumflos)}; klør som trumf ved vip og halve ${factor(points.klor)} (ikke ved en almindelig melding); hvert bank ${factor(points.bank)}.`,
    "Bet: indsatsen (præcis) pr. manglende stik, ganget med de samme fordoblinger.",
    "Hver taber betaler hver vinder beløbet; selvmakker mod alle tre. Sol-meldingerne: hver sol-spiller afregner et fast beløb med hver af de tre andre, også andre sol-spillere.",
  ]
}

/** The cell of a lookup table in Danish: "1,5", or "–". */
export const lookupCell = (value: number | null) => (value === null ? "–" : amount(value))
