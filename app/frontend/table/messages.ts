// The messages TableChannel exchanges with the client: defined once here.
// The server builds them in TableCommands (state_message, rejection_message)
// from Hjerterfri::Round#view_for.

import type { CardCode } from "~/cards"

/** Seats are 0–3 in play order (clockwise). */
export type SeatIndex = number

export interface SeatInfo {
  seat: SeatIndex
  name: string
  bot: boolean
}

export interface TrickPlay {
  seat: SeatIndex
  card: CardCode
}

/** Everything one seat may know about the runde (Round#view_for). */
export interface SeatView {
  seat: SeatIndex
  phase: "playing" | "complete"
  hand: CardCode[]
  /** Cards left per other seat, keyed by seat index. */
  card_counts: Record<string, number>
  current_trick: TrickPlay[]
  last_trick: TrickPlay[]
  last_trick_winner: SeatIndex | null
  to_act: SeatIndex | null
  legal_moves: CardCode[]
  hearts_broken: boolean
  /** Runde points per seat; empty until the runde is complete. */
  points: number[]
  moon_shooter: SeatIndex | null
}

export interface TableState {
  table_id: number
  game_id: number
  round_number: number
  /** Grows with every play; a state with a lower version is stale. */
  version: number
  seats: SeatInfo[]
  view: SeatView
}

export type RejectionReason =
  | "round_complete"
  | "unknown_intent"
  | "not_your_turn"
  | "card_not_in_hand"
  | "must_lead_two_of_clubs"
  | "must_follow_suit"
  | "no_points_on_first_trick"
  | "hearts_not_broken"

export type ServerMessage =
  | { type: "state"; state: TableState }
  | { type: "rejected"; reason: RejectionReason; card: CardCode }

/** Intents the client sends: TableChannel actions and their data. */
export interface ClientIntents {
  play: { card: CardCode }
}
