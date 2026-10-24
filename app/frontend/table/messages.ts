// The messages TableChannel exchanges with the client: defined once here.
// The server builds them in TableCommands (state_message, rejection_message,
// warning_message, leave, tick) from LiveGame#state_for,
// Hjerterfri::Round#view_for and Hjerterfri::Game.

import type { CardCode } from "~/cards"

/** Seats are 0–3 in play order (clockwise). */
export type SeatIndex = number

export type PassDirection = "left" | "right" | "across" | "none"

/** The table's rules config (Hjerterfri::Rules#to_h). */
export interface Rules {
  end_score: number
  queen_breaks_hearts: boolean
  jack_of_diamonds_minus_ten: boolean
  shooters_choice: boolean
}

export type RuleToggle = Exclude<keyof Rules, "end_score">

/** Hjerterfri::MoonChoice::OPTIONS: 26 to everyone else, or −26 to the shooter. */
export type MoonChoiceOption = "add_to_others" | "subtract_from_self"

export interface SeatInfo {
  seat: SeatIndex
  name: string
  bot: boolean
  /** The player a bot took this seat over from, when they forlod the spil. */
  took_over_from: string | null
  /** The player lost their connection and has not come back yet. */
  frakoblet: boolean
  /**
   * Seconds until this seat has forladt (TurnClock), counted from when the
   * message was built; null when no clock runs for it (bots, practice
   * tables, a connected seat that is not to act).
   */
  seconds_left: number | null
}

export interface TrickPlay {
  seat: SeatIndex
  card: CardCode
}

/** Everything one seat may know about the runde (Round#view_for). */
export interface SeatView {
  seat: SeatIndex
  /** "choosing_moon": all stik are played and the moon shooter is to choose (shooter's choice). */
  phase: "passing" | "playing" | "choosing_moon" | "complete"
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
  /** What the moon shooter chose; null until chosen, and without shooter's choice. */
  moon_choice: MoonChoiceOption | null
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
  /**
   * The vindere: human seats with the lowest total (ties share; a human tied
   * with a bot wins). Empty until the spil is over, and when a bot alone has
   * the lowest total.
   */
  winners: SeatIndex[]
}

export interface TableState {
  table_id: number
  /** Table#kind: a practice table (you and three bots) or an open one. */
  table_kind: "practice" | "open"
  game_id: number
  status: "in_progress" | "finished" | "abandoned"
  round_number: number
  /** Grows with every pass, play and deal; a state with a lower version is stale. */
  version: number
  rules: Rules
  seats: SeatInfo[]
  view: SeatView
  /** Points each seat has taken in this runde's completed stik (no moon adjustment). */
  points_taken: number[]
  score: Score
  /** The turn timer: a warning after `warning` seconds, forladt after `limit`. */
  timer: { warning: number; limit: number }
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
  | "choosing_moon"
  | "not_choosing_moon"
  | "unknown_moon_choice"

export type ServerMessage =
  | { type: "state"; state: TableState }
  | { type: "rejected"; reason: RejectionReason; card?: CardCode; cards?: CardCode[]; option?: string }
  /** The table was closed (the player left); go back to the lobby. */
  | { type: "closed" }
  /** You have forladt the spil (left, or away too long); a bot took your seat. */
  | { type: "forladt" }
  /** The spil is over and someone stood up: the bord waits for players again. */
  | { type: "waiting" }
  /** Your turn has run for the warning time; you forlader when it runs out. */
  | { type: "turn_warning"; seconds_left: number }

/** Intents the client sends: TableChannel actions and their data. */
export interface ClientIntents {
  pass: { cards: CardCode[] }
  play: { card: CardCode }
  /** The moon shooter's choice under shooter's choice. */
  choose_moon: { option: MoonChoiceOption }
  /** Deal the next runde now instead of waiting out the pause. */
  next_runde: Record<string, never>
  /** "Spil igen" once the spil is finished. */
  play_again: Record<string, never>
  /** The keep-alive, every few seconds while connected. */
  heartbeat: Record<string, never>
}
