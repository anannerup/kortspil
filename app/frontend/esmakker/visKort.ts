import type { SeatIndex } from "~/table/messages"
import { meldingLabel } from "./bidding.ts"
import type { EsmakkerThought } from "./messages"
import { signedPoints } from "./score.ts"

/**
 * "Vis kort" at es-makker: a bot's thought (Esmakker::Bot::Decision) in
 * one line: what it does and why, then what it expects of the runde, "—"
 * for what it does not know. Pure: it only words what the server sent.
 */

const RANDOM: Record<EsmakkerThought["decision"], string> = {
  bid: "Tilfældig melding",
  pas: "Pas",
  choose_trump: "Tilfældig lovlig trumf",
  call_ace: "Tilfældigt lovligt es",
  turn_card: "Vender tilfældigt næste kort",
  accept_trump: "Tilfældigt: det er trumf",
  discard: "Tilfældige kort lagt væk",
  lay_fordaekt: "Tilfældigt kort lagt fordækt",
  play: "Tilfældigt lovligt kort",
}

const UNKNOWN = "—"
const known = (value: number | string | null) => (value === null ? UNKNOWN : String(value))

/** "Melder 9", "Pas (9 er ikke lovlig)", "Tilfældigt lovligt kort". */
export function thoughtDecision(thought: EsmakkerThought): string {
  const melding = thought.melding ? meldingLabel(thought.melding) : UNKNOWN
  if (thought.reason === "fixed_melding") return `Melder ${melding}`
  if (thought.reason === "not_legal") return `Pas (${melding} er ikke lovlig)`
  return RANDOM[thought.decision]
}

/** "melding 9 · stik — (makker —) · makker — · point —": the bot's estimates for the runde. */
export function thoughtExpectations(thought: EsmakkerThought, nameOf: (seat: SeatIndex) => string): string {
  const { melding, stik, makker, points } = thought.expect
  return [
    `melding ${melding ? meldingLabel(melding) : UNKNOWN}`,
    `stik ${known(stik.self)} (makker ${known(stik.makker)})`,
    `makker ${makker === null ? UNKNOWN : nameOf(makker)}`,
    `point ${points === null ? UNKNOWN : signedPoints(points)}`,
  ].join(" · ")
}

export function esmakkerThoughtLine(thought: EsmakkerThought, nameOf: (seat: SeatIndex) => string): string {
  return `${thoughtDecision(thought)} — ${thoughtExpectations(thought, nameOf)}`
}
