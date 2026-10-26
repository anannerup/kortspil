import type { SeatIndex } from "~/table/messages"
import { meldingLabel } from "./bidding.ts"
import type { EsmakkerThought, SvaerReason } from "./messages"
import { signedPoints } from "./score.ts"

/**
 * "Vis kort" at es-makker: a bot's thought (Esmakker::Bot::Decision) in
 * one line: what it does and why, then what it expects of the runde, "—"
 * for what it does not know. Pure: it only words what the server sent.
 */

const RANDOM: Record<EsmakkerThought["decision"], string> = {
  bid: "Tilfældig melding",
  pas: "Pas",
  det_kan_jeg_selv: "Det kan jeg selv",
  gaa_med: "Går med",
  choose_trump: "Tilfældig lovlig trumf",
  call_ace: "Tilfældigt lovligt es",
  turn_card: "Vender tilfældigt næste kort",
  accept_trump: "Tilfældigt: det er trumf",
  discard: "Tilfældige kort lagt væk",
  lay_fordaekt: "Tilfældigt kort lagt fordækt",
  play: "Tilfældigt lovligt kort",
}

/** Svær's reasons (strategy §6), each a line; `m` is the melding the reason is about. */
const SVAER: Record<SvaerReason, (m: string) => string> = {
  bid_lowest: (m) => `Melder ${m}: laveste trin med bedst forventet gevinst`,
  bid_gode: (m) => `Melder ${m}: klør er (næsten) bedste trumf, med et stiks margin`,
  bid_halve: (m) => `Melder ${m}: gode kort i alle de andre farver`,
  bid_vip: (m) => `Melder ${m}: hånden klarer det med enhver trumf`,
  sol_test: (m) => `Sol-testen holder til ${m}`,
  within_reach: (m) => `Det kan jeg selv: ${m} er inden for rækkevidde`,
  pas_weak: () => "Pas: for svag til 8 og ingen sol",
  pas_too_high: () => "Pas: meldingen er over, hvad hånden kan bære",
  best_trump: () => "Trumf: farven med flest forventede stik",
  trumfloes: () => "Trumfløs: næsten lige så mange stik, og dobbelt op",
  call_shortest: () => "Kalder es i den korteste farve uden eget es",
  vip_accept: () => "Det er trumf: kortet giver stik nok",
  vip_turn: () => "Vender næste kort: trumfen giver ikke stik nok",
  discard_void: () => "Lægger væk: tømmer den korteste sidefarve, så den kan stikkes",
  discard_low: () => "Lægger væk: lave kort fra den svageste sidefarve",
  sol_discard: () => "Lægger væk: de høje kort fra de farligste farver",
  fordaekt: () => "Lægger fordækt: udspillet til makker",
  draw_trump: () => "Trækker trumf fra toppen (gode trumf)",
  makker_in: () => "Spiller makker ind",
  signal_suit: () => "Spiller den farve, medspilleren smed",
  cash: () => "Tager et sikkert stik",
  joker_lead: () => "Spiller joker ud: et sikkert stik",
  long_suit: () => "Spiller fra den lange farve",
  trump_last: () => "Spiller trumf: intet andet at spille",
  makker_trump: () => "Spiller trumf som makker",
  show_ace: () => "Spiller esset ud og viser sig",
  return_suit: () => "Returnerer medspillerens farve",
  top_trump: () => "Spiller den højeste trumf: to for én",
  lay_ace: () => "Lægger det kaldte es",
  makker_wins: () => "Makker tager stikket: lægger lavt",
  follow_sequence: () => "Lægger det laveste af en høj sekvens",
  follow_low: () => "Bekender lavt",
  follow_win: () => "Tager stikket så lavt som muligt",
  no_finesse: () => "Tager stikket sikkert: ingen finesse, før meldingen er hjemme",
  ruff: () => "Stikker med laveste trumf",
  afkast: () => "Smider et lavt kort",
  afkast_renonce: () => "Smider fra farven, den vil være renonce i",
  afkast_spil: () => "Smider fra farven, den vil have spillet",
  sol_take: () => "Tager sit ene stik nu med et farligt kort",
  sol_lead: () => "Spiller lavt ud fra en sikker farve",
  sol_under: () => "Lægger det højeste kort under stikket",
  sol_high: () => "Kan ikke komme under: lægger det højeste",
  sol_afkast: () => "Smider et farligt højt kort",
  sol_defend_lead: () => "Spiller ud mod sol-spilleren",
  sol_defend_afkast: () => "Smider det højeste kort fra en kort farve",
  sol_cover: () => "Dækker et meget lavt udspil",
  sol_defend_under: () => "Lægger det højeste kort under sol-spillerens",
  sol_defend_low: () => "Lægger lavt",
  any: () => "Spiller det laveste kort",
}

const FIRST_BOT = new Set(["fixed_melding", "not_legal", "random"])

const UNKNOWN = "—"
const known = (value: number | string | null) => (value === null ? UNKNOWN : String(value).replace(".", ","))

/** "Melder 9", "Pas (9 er ikke lovlig)", "Tilfældigt lovligt kort"; Svær's reason in words. */
export function thoughtDecision(thought: EsmakkerThought): string {
  const melding = thought.melding ? meldingLabel(thought.melding) : UNKNOWN
  if (thought.reason === "fixed_melding") return `Melder ${melding}`
  if (thought.reason === "not_legal") return `Pas (${melding} er ikke lovlig)`
  if (!FIRST_BOT.has(thought.reason)) return SVAER[thought.reason as SvaerReason](melding)
  return RANDOM[thought.decision]
}

/** "melding 9 · stik 5,5 (makker 2) · makker Bot 2 · point +1,5": the bot's estimates for the runde. */
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
