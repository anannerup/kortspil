// The es-makker messages: the bord's rules (Esmakker::Rules#to_h, also in
// the lobby entry) and the "state" TableChannel sends at an es-makker
// table (Game::State#state_for with Esmakker::Round#view_for). Defined
// once here.

import type { CardCode, Suit } from "~/cards"
import type { SeatIndex, SeatInfo, TrickPlay } from "~/table/messages"

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

/**
 * A melding's code (Esmakker::Melding#to_s): a number 8–13 with or without
 * a påhæng ("9", "10halve", "11vip"), or a sol-melding ("sol", "ren_sol",
 * "bordlaegger", "ren_bordlaegger").
 */
export type MeldingCode = string

/** One step of the meldingsrunde; `melding` is the melding standing after it. */
export interface BiddingEntry {
  seat: SeatIndex
  action: "bid" | "pas" | "det_kan_jeg_selv" | "gaa_med" | "jernhaand"
  melding: MeldingCode | null
}

/** How the meldingsrunde ended (Esmakker::Bidding::Outcome#to_h). */
export type BiddingOutcome =
  | { kind: "melder"; melder: SeatIndex; melding: MeldingCode; went_with: SeatIndex[]; reason: null; dealer: null }
  /** Dealt again: everybody passed (the former forhånd deals) or a jernhånd was claimed (the same kortgiver deals). */
  | { kind: "redeal"; melder: null; melding: null; went_with: []; reason: "all_passed" | "jernhaand"; dealer: SeatIndex }

/** The meldingsrunde as everybody sees it (Esmakker::Bidding#view): all of it is public. */
export interface BiddingView {
  phase: "bidding" | "complete"
  forhand: SeatIndex
  dealer: SeatIndex
  /** Whose turn it is; null once it is over. */
  to_act: SeatIndex | null
  /** The melding standing now, and who holds it. */
  melding: MeldingCode | null
  holder: SeatIndex | null
  /** The holder who may say "det kan jeg selv" now (she is also to act). */
  serveret: SeatIndex | null
  passed: SeatIndex[]
  /** The seats that went with the standing sol-melding. */
  went_with: SeatIndex[]
  history: BiddingEntry[]
  outcome: BiddingOutcome | null
}

/** What this seat may choose now (Esmakker::Round#choices); the server decides. */
export interface BiddingChoices {
  /** The meldinger it may bid, lowest first. */
  meldinger: MeldingCode[]
  det_kan_jeg_selv: boolean
  gaa_med: boolean
  pas: boolean
  /** Claim a jernhånd (only its holder, before the first bid). */
  jernhaand: boolean
  /** The declarer (the melder; at halve the ace's holder): the trumps she may name (suits, then "trumfloes"). */
  trumps: TrumpCode[]
  /** The melder: the aces she may call, by suit. */
  aces: Suit[]
  /** Vip, the melder: turn the kitty's next card ("Vend kort"). */
  turn_card: boolean
  /** Vip, the melder: take the card turned last as trump ("Det er trumf"). */
  accept_trump: boolean
  /**
   * Vip, in the bank window: "Bank". Before the first bank every seat but the melder's
   * is offered it alike (the esmakker too, so it does not give her away); after it the melder alone.
   */
  bank: boolean
  /** The declarer holds the kitty and is to lay three cards away; at a sol-melding, the seat exchanging lays as many away as it took up (SolPlayView.discard_size). */
  discard: boolean
  /** The melder, before she leads stik 1, void in the called ace's suit: the cards she may lay fordækt. */
  fordaekt: CardCode[]
}

/** Trump (Esmakker::Trump#to_s): a suit, or "trumfloes". */
export type TrumpCode = Suit | "trumfloes"

/** The play of a stik melding as this seat may see it (Esmakker::Play#view_for). */
export interface PlayView {
  /** Only the sol play says what it is (SolPlayView). */
  kind?: undefined
  trump: TrumpCode | null
  /** The called ace's suit, once called. */
  called_ace: Suit | null
  /** Who holds the called ace: only once this seat knows (her own seat, after the ace is played, or at halve from the call). */
  esmakker: SeatIndex | null
  /** The melder plays alone (the ace lay in the kitty); only once this seat knows (at halve everyone, from the call). */
  selvmakker: boolean
  /** Vip: the kitty's cards turned face up so far, in order (everyone sees them; the others stay hidden). */
  turned: CardCode[]
  /** Vip: which turned card became trump, 1–3, once taken. */
  vip_card: number | null
  /** Vip: the bank window is open (after trump is named, before the melder takes the kitty up). */
  bank_window: boolean
  /** Vip: who banked, in order (at most two; the second is the melder's). Each bank doubles. */
  banks: SeatIndex[]
  /** The declarer only, while she lays away: the cards that came from the kitty. */
  kitty_cards: CardCode[]
  /** The declarer only: the three cards she laid away. */
  discarded: CardCode[]
  current_trick: TrickPlay[]
  last_trick: TrickPlay[]
  last_trick_winner: SeatIndex | null
  /** Stik taken per seat (public). */
  tricks_won: number[]
  /** Stik per side, once this seat knows who plays with the melder. */
  side_stik: { melder: number; modspillere: number } | null
  /** The cards this seat may play now (the melder's fordækt card among them, by its own code). */
  legal_moves: CardCode[]
  /** The melder's fordækt card, once laid. */
  fordaekt: FordaektView | null
}

/** The face-down card of fordækt (Esmakker::Play#fordaekt_view). */
export interface FordaektView {
  /** The melder's seat. */
  seat: SeatIndex
  /** Its face: the melder's own, everyone's once its stik is taken; null while hidden. */
  card: CardCode | null
  /** It lies on the table, not played yet. */
  waiting: boolean
  /** Its stik is taken, so it is turned. */
  turned: boolean
}

/**
 * The play of a sol-melding (sol, ren sol, bordlægger, ren bordlægger) as this seat may see it (Esmakker::SolPlay#view_for):
 * no trump, no ace, no makker; the stik melding's fields are there, empty.
 */
export interface SolPlayView extends Omit<PlayView, "kind" | "trump" | "called_ace" | "esmakker" | "selvmakker" | "side_stik" | "fordaekt"> {
  kind: "sol"
  trump: null
  called_ace: null
  esmakker: null
  selvmakker: false
  side_stik: null
  fordaekt: null
  /** Who plays the sol-melding: the melder, then those who went with, in order. */
  players: SeatIndex[]
  /** The most stik a sol player may take: sol and bordlægger 1, ren sol and ren bordlægger 0. */
  most_stik: number
  /** The sol players who took one stik too many. */
  vaeltet: SeatIndex[]
  /** Who exchanges with the kitty, in turn: the melder, those who went with, then clockwise from the melder. */
  exchange_order: SeatIndex[]
  /** The seat exchanging now; null once the stik have started. */
  exchanging: SeatIndex | null
  /** How many cards the seat exchanging holds of the kitty, and lays away. */
  discard_size: number
  /** Bordlægger, ren bordlægger: the melder's cards, open to everyone from the end of the first stik (as she holds them now); null before that and at sol. */
  open_hand: OpenHandView | null
}

/** The bordlægger's open hand (Esmakker::SolPlay#open_hand). */
export interface OpenHandView {
  seat: SeatIndex
  cards: CardCode[]
}

/** A sol-melding's own part of its result. */
export interface SolResultPart {
  players: SeatIndex[]
  most_stik: number
  vaeltet: SeatIndex[]
}

/** How a runde with a melder ended (Esmakker::RundeResult#to_h), with its points per seat. */
export interface RundeResultView {
  /** "played": a stik melding; "sol": a sol-melding (sol, ren sol, bordlægger, ren bordlægger), settled per sol player (`sol`). */
  kind: "played" | "sol"
  melder: SeatIndex
  melding: MeldingCode
  trump: TrumpCode | null
  called_ace: Suit | null
  esmakker: SeatIndex | null
  selvmakker: boolean
  tricks_won: number[]
  /** Stik of the melder's side. */
  stik: number
  gik_hjem: boolean
  /** Vip: the kitty card the melder took as trump, 1–3; null otherwise. */
  vip_card: number | null
  /** The number of banks (ticket 08). */
  banks: number
  /** Points won (+) or lost (−) per seat; they sum to 0. A melding not played scores 0. */
  points: number[]
  /** Sol and ren sol only: who played it, the stik it allowed and who was væltet. */
  sol?: SolResultPart
}

/** Vip's open bank window (Game::State#bank_window_state). */
export interface BankWindow {
  /** The bord's window, 5–10 seconds. */
  seconds: number
  /** Seconds left when the server built the state. */
  seconds_left: number
  closes_at: string
}

/** A completed runde on the score sheet: its result and the totals after it. */
export interface ScoreRow extends RundeResultView {
  totals: number[]
}

/** Everything one seat may know about an es-makker runde (Esmakker::Round#view_for). */
export interface EsmakkerView {
  seat: SeatIndex
  /** The meldingsrunde; a redeal; the melder's trump, ace, vip's turns and kitty; the stik; the runde over. */
  phase: EsmakkerPhase
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
  /** Whose turn it is, or nobody's. */
  to_act: SeatIndex | null
  bidding: BiddingView
  choices: BiddingChoices
  /** The play once a melding is played (null before, and for a melding not played yet). */
  play: PlayView | SolPlayView | null
  /** The runde's result once complete. */
  result: RundeResultView | null
}

export type EsmakkerPhase = "bidding" | "redeal" | "choosing_trump" | "calling_ace" | "turning" | "banking" | "discarding" | "exchanging" | "playing" | "complete"

export interface EsmakkerTableState {
  table_id: number
  table_kind: "open" | "password" | "private"
  game: "esmakker"
  game_id: number
  status: "in_progress" | "finished" | "abandoned"
  /** The round rows dealt so far: a redeal is a new one. */
  round_number: number
  /** The number of runder the spil lasts. */
  runder: number
  /** The runde being played: a redeal is the same runde again. */
  runde: number
  /** Grows with every action and deal; a state with a lower version is stale. */
  version: number
  rules: EsmakkerRules
  seats: SeatInfo[]
  view: EsmakkerView
  /** Points per seat so far (zero-sum, from 0), the seats with the highest total, and every completed runde with the totals after it. */
  score: { totals: number[]; leaders: SeatIndex[]; results: ScoreRow[] }
  /** Vip's open bank window: its length and the seconds left when the state was built (count down from receiving it); null when none is open. */
  bank_window: BankWindow | null
  /** Once the spil is over: the new bord in the lobby where everyone waits for the next spil. */
  next_path?: string
  timer: { warning: number; limit: number }
}
