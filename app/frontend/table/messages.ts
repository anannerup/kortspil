// The messages TableChannel exchanges with the client: defined once here.
// The server builds them in TableCommands (state_message, rejection_message,
// leave) from Hjerterfri::Round#view_for and Hjerterfri::Game.

import type { CardCode } from "~/cards"

/** Seats are 0–3 in play order (clockwise). */
export type SeatIndex = number

export type PassDirection = "left" | "right" | "across" | "none"

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
  phase: "passing" | "playing" | "complete"
  pass_direction: PassDirection
  /** The cards this seat passed; empty until it has passed. */
  own_pass: CardCode[]
  /** Who has passed so far (never what they passed). */
  passed_seats: SeatIndex[]
  /** The cards this seat received; empty until all four have passed. */
  received_cards: CardCode[]
  hand: CardCode[]
  /** Cards left per other seat, keyed by seat index. */
  card_counts: Record<string, number>
  current_trick: TrickPlay[]
  last_trick: TrickPlay[]
  last_trick_winner: SeatIndex | null
  to_act: SeatIndex | null
  legal_moves: CardCode[]
  hearts_broken: boolean
  /** Runde points per seat incl. the moon; empty until the runde is complete. */
  points: number[]
  moon_shooter: SeatIndex | null
  jack_of_diamonds_taker: SeatIndex | null
}

/** One completed runde on the score sheet (Hjerterfri::Game#rows). */
export interface ScoreRow {
  number: number
  pass_direction: PassDirection
  points: number[]
  /** Running totals after this runde. */
  totals: number[]
}

export interface Score {
  end_score: number
  rows: ScoreRow[]
  totals: number[]
  /** Seats with the lowest total; empty before the first runde is done. */
  leaders: SeatIndex[]
  /** Seats that won (ties share); empty until the spil is over. */
  winners: SeatIndex[]
}

export interface TableState {
  table_id: number
  game_id: number
  status: "in_progress" | "finished" | "abandoned"
  round_number: number
  /** Grows with every pass, play and deal; a state with a lower version is stale. */
  version: number
  seats: SeatInfo[]
  view: SeatView
  /** Points each seat has taken in this runde's completed stik (no moon adjustment). */
  points_taken: number[]
  score: Score
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
  | "not_passing"
  | "already_passed"
  | "wrong_card_count"
  | "duplicate_cards"
  | "passing_not_complete"

export type ServerMessage =
  | { type: "state"; state: TableState }
  | { type: "rejected"; reason: RejectionReason; card?: CardCode; cards?: CardCode[] }
  /** The table was closed (the player left); go back to the lobby. */
  | { type: "closed" }

/** Intents the client sends: TableChannel actions and their data. */
export interface ClientIntents {
  pass: { cards: CardCode[] }
  play: { card: CardCode }
  /** Deal the next runde now instead of waiting out the pause. */
  next_runde: Record<string, never>
  /** "Spil igen" once the spil is finished. */
  play_again: Record<string, never>
}
