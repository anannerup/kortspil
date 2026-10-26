import type { EsmakkerPoints, EsmakkerRules, Pahaeng, StakeNumber } from "./messages"

/**
 * Es-makker's rules in words, and the settings form the vært sends
 * (Esmakker::Rules.from_form, TableRules.cast). Pure: labels only; the
 * server decides what is allowed.
 */

export const PAHAENG_NAMES: Record<Pahaeng, string> = { vip: "Vip", halve: "Halve", gode: "Gode" }

export const STAKE_NUMBERS: StakeNumber[] = ["8", "9", "10", "11", "12", "13"]

/** The factors and fixed amounts after the stakes, in the order the panel shows them. */
export const POINT_LABELS: { key: Exclude<keyof EsmakkerPoints, "stakes">; label: string; factor: boolean }[] = [
  { key: "pahaeng", label: "Påhæng", factor: true },
  { key: "trumflos", label: "Trumfløs", factor: true },
  { key: "klor", label: "Klør ved vip og halve", factor: true },
  { key: "vip_first", label: "Vip, kattens 1. kort", factor: true },
  { key: "vip_second", label: "Vip, kattens 2. kort", factor: true },
  { key: "vip_third", label: "Vip, kattens 3. kort", factor: true },
  { key: "bank", label: "Bank", factor: true },
  { key: "sol", label: "Sol", factor: false },
  { key: "ren_sol", label: "Ren sol", factor: false },
  { key: "bordlaegger", label: "Bordlægger", factor: false },
  { key: "ren_bordlaegger", label: "Ren bordlægger", factor: false },
]

/** "1,5": amounts in Danish. */
export const amount = (value: number) => String(value).replace(".", ",")

/** "Vip > Halve > Gode" */
export const pahaengLine = (order: Pahaeng[]) => order.map((pahaeng) => PAHAENG_NAMES[pahaeng]).join(" > ")

export const runderLabel = (runder: number | null) => (runder === 1 ? "1 runde" : `${runder ?? "?"} runder`)

/** The rules in short, for the lobby: "10 runder · Vip > Halve > Gode · Jokere kan stikkes". */
export function esmakkerSummary(rules: EsmakkerRules, runder: number | null): string {
  return [runderLabel(runder), pahaengLine(rules.pahaeng_order), rules.joker_trumpable ? "Jokere kan stikkes med trumf" : "Jokere kan ikke stikkes"].join(" · ")
}

/** `order` with the påhæng at `index` moved one tier up (-1) or down (+1). */
export function movePahaeng(order: Pahaeng[], index: number, by: -1 | 1): Pahaeng[] {
  const to = index + by
  if (to < 0 || to >= order.length) return order
  const moved = [...order]
  const [pahaeng] = moved.splice(index, 1)
  if (pahaeng) moved.splice(to, 0, pahaeng)
  return moved
}

/**
 * The whole settings form, as WaitingTables::SettingsController reads it
 * (FormData field names): the table type, the number of runder, and
 * es-makker's rules. The påhæng order goes as one field, "vip,halve,gode".
 */
export function esmakkerSettingsFields(rules: EsmakkerRules, runder: number | null, kind: string, password = ""): Record<string, string> {
  const fields: Record<string, string> = {
    kind,
    runder: String(runder ?? ""),
    "rules[pahaeng_order]": rules.pahaeng_order.join(","),
    "rules[joker_trumpable]": rules.joker_trumpable ? "1" : "0",
    "rules[esmakker_banks_first]": rules.esmakker_banks_first ? "1" : "0",
    "rules[bank_window]": String(rules.bank_window),
  }
  for (const number of STAKE_NUMBERS) fields[`rules[points][stakes][${number}]`] = String(rules.points.stakes[number])
  for (const { key } of POINT_LABELS) fields[`rules[points][${key}]`] = String(rules.points[key])
  if (password) fields.password = password
  return fields
}
