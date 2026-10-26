// The messages TableChannel exchanges with the client: defined once here.
// The server builds them in the bord's actions (Table: state_message,
// rejection_message, warning_message, leave, chat, heartbeat) from
// Game#state_for, Hjerterfri::Round#view_for, Hjerterfri::Game and TableChat.

import type { CardCode } from "~/cards"
import type { BotLevel } from "~/lobby/messages"

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
  /** The bot's level (Let, Mellem or Svær); null for a human. */
  bot_level: BotLevel | null
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
  /** Table#kind: a practice table (you and three bots), or one the vært chose the type of. */
  table_kind: "practice" | "open" | "password" | "private"
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
  /** Once the spil is over: the new bord in the lobby where everyone at this one waits for the next spil (Table::Playing#spil_over). */
  next_path?: string
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
  // Es-makker's meldingsrunde (Esmakker::Bidding).
  | "bidding_complete"
  | "bidding_started"
  | "no_jernhaand"
  | "nothing_to_take_over"
  | "not_sol_melding"
  | "det_kan_jeg_selv_or_pas"
  | "not_on_ladder"
  | "not_higher"
  | "not_now"
  | "unknown_trump"
  | "unknown_ace"
  | "own_ace"
  | "nothing_turned"
  | "trump_is_ace_suit"

/** One table chat message (TableChat::Entry): plain text, never HTML. */
export interface ChatEntry {
  /** Grows with every message, across tables. */
  id: number
  user_id: number
  /** The author's seat when they wrote it. */
  seat: SeatIndex
  name: string
  text: string
  /** ISO 8601, UTC. */
  at: string
}

/** TableChat's refusals: an empty message, one over max_length, or more than 5 in 10 seconds. */
export type ChatRejection = "blank" | "too_long" | "too_fast"

/** Chat messages; at a table that has not started, the only ones sent. */
export type ChatMessage =
  /** On (re)subscribing: the table's last 50 messages, oldest first. */
  | { type: "chat_history"; messages: ChatEntry[]; max_length: number }
  | { type: "chat_message"; message: ChatEntry }
  /** Your message was refused; only you get this. */
  | { type: "chat_rejected"; reason: ChatRejection }

export type ServerMessage =
  | ChatMessage
  | { type: "state"; state: TableState }
  | { type: "rejected"; reason: RejectionReason; card?: CardCode; cards?: CardCode[]; option?: string; melding?: string | null }
  /** The table was closed (the player left); go back to the lobby. */
  | { type: "closed" }
  /** You have forladt the spil (left, or away too long); a bot took your seat. */
  | { type: "forladt" }
  /** Go to the bord at `path` (no longer sent by the server since the end of the spil carries `next_path`). */
  | { type: "waiting"; path: string }
  /** Your turn has run for the warning time; you forlader when it runs out. */
  | { type: "turn_warning"; seconds_left: number }

/** Intents the client sends: TableChannel actions and their data. */
export interface ClientIntents {
  pass: { cards: CardCode[] }
  play: { card: CardCode }
  /** The moon shooter's choice under shooter's choice. */
  choose_moon: { option: MoonChoiceOption }
  /** Es-makker: bid a melding, by its code ("9", "10halve", "sol"). */
  bid: { melding: string }
  /** Es-makker: say pas (out of the meldingsrunde). */
  pas: Record<string, never>
  /** Es-makker: take over the melding the challenger just bid. */
  det_kan_jeg_selv: Record<string, never>
  /** Es-makker: go with the sol-melding. */
  gaa_med: Record<string, never>
  /** Es-makker: claim a jernhånd before the first bid; the runde is dealt again. */
  claim_jernhaand: Record<string, never>
  /** Es-makker: the melder names trump, a suit or "trumfloes". */
  choose_trump: { trump: string }
  /** Es-makker: the melder calls an ace by its suit (and takes the kitty up). */
  call_ace: { suit: string }
  /** Es-makker, vip: the melder turns the kitty's next card. */
  turn_card: Record<string, never>
  /** Es-makker, vip: the melder takes the card turned last as trump. */
  accept_trump: Record<string, never>
  /** Es-makker: the melder lays three cards away. */
  discard: { cards: CardCode[] }
  /** Deal the next runde now instead of waiting out the pause. */
  next_runde: Record<string, never>
  /** Say something at the table (seated players only). */
  chat: { text: string }
  /** The keep-alive, every few seconds while connected. */
  heartbeat: Record<string, never>
}
