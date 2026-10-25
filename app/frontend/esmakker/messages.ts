// The es-makker messages: the bord's rules (Esmakker::Rules#to_h, also in
// the lobby entry) and the "state" TableChannel sends at an es-makker
// table (Game::State#state_for with Esmakker::Round#view_for). Defined
// once here.

import type { CardCode } from "~/cards"
import type { SeatIndex, SeatInfo } from "~/table/messages"

/** A påhæng (REGLER §2.0): vip, halve or gode (clubs). */
export type Pahaeng = "vip" | "halve" | "gode"

/** The stakes per number, "8" … "13" (Esmakker::Points::NUMBERS). */
export type StakeNumber = "8" | "9" | "10" | "11" | "12" | "13"

/** The bord's point values (Esmakker::Points). Amounts may be halves. */
export interface EsmakkerPoints {
  stakes: Record<StakeNumber, number>
  pahaeng: number
  trumflos: number
  vip_first: number
  vip_second: number
  vip_third: number
  bank: number
  sol: number
  ren_sol: number
  bordlaegger: number
  ren_bordlaegger: number
}

/** Es-makker's GameRules (Esmakker::Rules#to_h). */
export interface EsmakkerRules {
  /** The påhæng from highest to lowest on one number; strict. */
  pahaeng_order: Pahaeng[]
  /** Whether trump beats a joker. */
  joker_trumpable: boolean
  /** Whether the esmakker may make the first bank at vip. */
  esmakker_banks_first: boolean
  /** Seconds the bank window stays open, 5–10. */
  bank_window: number
  points: EsmakkerPoints
}

/** Everything one seat may know about an es-makker runde (Esmakker::Round#view_for). */
export interface EsmakkerView {
  seat: SeatIndex
  /** "bidding": the meldingsrunde comes next (ticket 02). */
  phase: "bidding"
  /** Your own 13 cards; jokers are "X1"–"X3". */
  hand: CardCode[]
  /** Cards per other seat, keyed by seat index. */
  card_counts: Record<string, number>
  /** How many cards lie in the kitty (katten); never which. */
  kitty_count: number
  /** The kortgiver's seat. */
  dealer: SeatIndex
  /** The forhånd's seat: the one after the kortgiver. */
  forhand: SeatIndex
  /** Whose turn it is; nobody's until the meldingsrunde is built. */
  to_act: SeatIndex | null
}

export interface EsmakkerTableState {
  table_id: number
  table_kind: "open" | "password" | "private"
  game: "esmakker"
  game_id: number
  status: "in_progress" | "finished" | "abandoned"
  round_number: number
  /** The number of runder the spil lasts. */
  runder: number
  /** Grows with every action and deal; a state with a lower version is stale. */
  version: number
  rules: EsmakkerRules
  seats: SeatInfo[]
  view: EsmakkerView
  /** Points per seat so far (zero-sum; scoring comes later). */
  score: { totals: number[] }
  timer: { warning: number; limit: number }
}
