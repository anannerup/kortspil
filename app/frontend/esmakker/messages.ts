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
  /** The melder: the trumps she may name (suits, then "trumfloes"). */
  trumps: TrumpCode[]
  /** The melder: the aces she may call, by suit. */
  aces: Suit[]
  /** The melder holds the kitty and is to lay three cards away. */
  discard: boolean
  /** The melder, before she leads stik 1, void in the called ace's suit: the cards she may lay fordækt. */
  fordaekt: CardCode[]
}

/** Trump (Esmakker::Trump#to_s): a suit, or "trumfloes". */
export type TrumpCode = Suit | "trumfloes"

/** The play of a stik melding as this seat may see it (Esmakker::Play#view_for). */
export interface PlayView {
  trump: TrumpCode | null
  /** The called ace's suit, once called. */
  called_ace: Suit | null
  /** Who holds the called ace: only once this seat knows (her own seat, or after the ace is played). */
  esmakker: SeatIndex | null
  /** The melder plays alone (the ace lay in the kitty); only once this seat knows. */
  selvmakker: boolean
  /** The melder only, while she lays away: the cards that came from the kitty. */
  kitty_cards: CardCode[]
  /** The melder only: the three cards she laid away. */
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

/** How a runde with a melder ended (Esmakker::RundeResult#to_h); points come later. */
export interface RundeResultView {
  /** "not_played": a melding whose play comes in a later version (halve, vip, sol-meldinger). */
  kind: "played" | "not_played"
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
  points: number[]
}

/** Everything one seat may know about an es-makker runde (Esmakker::Round#view_for). */
export interface EsmakkerView {
  seat: SeatIndex
  /** The meldingsrunde; a redeal; the melder's trump, ace and kitty; the stik; the runde over. */
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
  play: PlayView | null
  /** The runde's result once complete. */
  result: RundeResultView | null
}

export type EsmakkerPhase = "bidding" | "redeal" | "choosing_trump" | "calling_ace" | "discarding" | "playing" | "complete"

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
  /** Points per seat so far (zero-sum; scoring comes later) and every completed runde's result. */
  score: { totals: number[]; results: RundeResultView[] }
  /** Once the spil is over: the new bord in the lobby where everyone waits for the next spil. */
  next_path?: string
  timer: { warning: number; limit: number }
}
