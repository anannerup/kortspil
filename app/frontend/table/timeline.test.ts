import { describe, expect, test } from "vitest"
import type { SeatView, TableState, TrickPlay } from "./messages"
import { FLY_MS, PASS_AWAY_MS, PAUSE_MS, SWEEP_MS, framesFor, type Frame } from "./timeline"

const view = (over: Partial<SeatView> = {}): SeatView => ({
  seat: 0,
  phase: "playing",
  pass_direction: "left",
  own_pass: [],
  passed_seats: [],
  received_cards: [],
  hand: ["2H", "3H"],
  card_counts: { "1": 2, "2": 2, "3": 2 },
  current_trick: [],
  last_trick: [],
  last_trick_winner: null,
  to_act: 1,
  legal_moves: [],
  hearts_broken: false,
  points: [],
  moon_shooter: null,
  moon_choice: null,
  jack_of_diamonds_taker: null,
  ...over,
})

let version = 0
const state = (over: Partial<SeatView> = {}, rest: Partial<TableState> = {}): TableState => ({
  table_id: 1,
  table_kind: "practice",
  game_id: 1,
  status: "in_progress",
  round_number: 1,
  version: ++version,
  rules: { end_score: 100, queen_breaks_hearts: false, jack_of_diamonds_minus_ten: false, shooters_choice: false },
  seats: [],
  view: view(over),
  points_taken: [0, 0, 0, 0],
  score: { end_score: 100, rows: [], totals: [0, 0, 0, 0], leaders: [], winners: [] },
  play_again_seats: [],
  timer: { warning: 30, limit: 60 },
  ...rest,
})

const plays = (...codes: string[]): TrickPlay[] => codes.map((card, seat) => ({ seat, card }))
const first = (s: TableState) => framesFor(null, s, false)[0] as Frame

describe("framesFor", () => {
  test("the first state shows as it is", () => {
    const s = state({ current_trick: plays("2C") })
    expect(framesFor(null, s, false)).toEqual([{ state: s, trick: plays("2C"), sweepTo: null, passTo: null, lastTrick: { plays: [], winner: null }, hold: 0 }])
  })

  test("a played card holds until it has landed", () => {
    const shown = first(state({ current_trick: plays("2C") }))
    const [frame] = framesFor(shown, state({ current_trick: plays("2C", "5C") }), false)
    expect(frame?.trick).toEqual(plays("2C", "5C"))
    expect(frame?.hold).toBe(FLY_MS + 60)
  })

  test("a completed stik rests, sweeps to its winner, then the table moves on", () => {
    const shown = first(state({ current_trick: plays("2C", "5C", "9C") }))
    const next = state(
      { current_trick: [], last_trick: plays("2C", "5C", "9C", "KC"), last_trick_winner: 3, to_act: 3, hand: ["3H"] },
      { points_taken: [0, 0, 0, 1] },
    )
    const [resting, leaving, settled] = framesFor(shown, next, false)

    expect(resting?.trick).toEqual(plays("2C", "5C", "9C", "KC"))
    expect(resting?.sweepTo).toBeNull()
    expect(resting?.hold).toBe(FLY_MS + PAUSE_MS)
    expect(leaving?.sweepTo).toBe(3)
    expect(leaving?.hold).toBe(SWEEP_MS)
    expect(settled).toEqual({ state: next, trick: [], sweepTo: null, passTo: null, lastTrick: { plays: next.view.last_trick, winner: 3 }, hold: 0 })
  })

  test("while the stik lies on the table, points, Sidste stik and the turn wait", () => {
    const earlier = plays("4D", "6D", "8D", "TD")
    const shown = first(state({ current_trick: plays("2C", "5C", "9C"), last_trick: earlier, last_trick_winner: 1 }, { points_taken: [0, 0, 0, 0] }))
    const next = state({ last_trick: plays("2C", "5C", "9C", "QS"), last_trick_winner: 3, to_act: 3, legal_moves: ["3H"] }, { points_taken: [0, 0, 0, 13] })
    for (const frame of framesFor(shown, next, false).slice(0, 2)) {
      expect(frame.state.points_taken).toEqual([0, 0, 0, 0])
      expect(frame.lastTrick).toEqual({ plays: earlier, winner: 1 })
      expect(frame.state.view.to_act).toBeNull()
      expect(frame.state.view.legal_moves).toEqual([])
      expect(frame.state.view.hand).toEqual(next.view.hand)
    }
  })

  test("the runde result waits until the last stik has left the table", () => {
    const shown = first(state({ current_trick: plays("2C", "5C", "9C") }))
    const next = state(
      { phase: "complete", last_trick: plays("2C", "5C", "9C", "KC"), last_trick_winner: 3, to_act: null, points: [0, 0, 0, 26] },
      { score: { end_score: 100, rows: [], totals: [0, 0, 0, 26], leaders: [0], winners: [] } },
    )
    const [resting, leaving, settled] = framesFor(shown, next, false)
    expect(resting?.state.view.phase).toBe("playing")
    expect(leaving?.state.score.totals).toEqual([0, 0, 0, 0])
    expect(settled?.state.view.phase).toBe("complete")
  })

  test("with reduced motion, a completed stik shows the new state at once", () => {
    const shown = first(state({ current_trick: plays("2C", "5C", "9C") }))
    const next = state({ last_trick: plays("2C", "5C", "9C", "KC"), last_trick_winner: 3 })
    expect(framesFor(shown, next, true)).toEqual([{ state: next, trick: [], sweepTo: null, passTo: null, lastTrick: { plays: next.view.last_trick, winner: 3 }, hold: 0 }])
  })

  test("when the pass is done, your cards slide to their receiver before the new ones come", () => {
    // You pass last: the state before has not seen your pass yet.
    const shown = first(state({ phase: "passing", pass_direction: "right", own_pass: [], passed_seats: [1, 2, 3], hand: ["2C", "3C", "QS", "AH", "KH"] }))
    const next = state(
      { phase: "playing", pass_direction: "right", own_pass: ["QS", "AH", "KH"], passed_seats: [0, 1, 2, 3], received_cards: ["4D"], hand: ["2C", "3C", "4D"] },
      { seats: [0, 1, 2, 3].map((seat) => ({ seat, name: `S${seat}`, bot: seat > 0, took_over_from: null, frakoblet: false, seconds_left: null })) },
    )
    const [away, settled] = framesFor(shown, next, false)
    expect(away?.passTo).toBe(3)
    expect(away?.state.view.phase).toBe("passing")
    expect(away?.state.view.hand).toEqual(["2C", "3C"])
    expect(away?.state.view.own_pass).toEqual(["QS", "AH", "KH"])
    expect(away?.state.view.passed_seats).toEqual([0, 1, 2, 3])
    expect(away?.hold).toBe(PASS_AWAY_MS)
    expect(settled?.state).toBe(next)
    expect(framesFor(shown, next, true)).toHaveLength(1)
  })

  test("the cards slide off as soon as every seat has passed, before the deal", () => {
    const shown = first(state({ phase: "passing", pass_direction: "left", own_pass: [], passed_seats: [1, 2, 3], hand: ["2C", "QS", "AH", "KH"] }))
    const allIn = state({ phase: "passing", pass_direction: "left", own_pass: ["QS", "AH", "KH"], passed_seats: [0, 1, 2, 3], hand: ["2C"] })
    const [away] = framesFor(shown, allIn, false)
    expect(away?.passTo).toBe(1)
    expect(away?.hold).toBe(PASS_AWAY_MS)
    const dealt = state({ phase: "playing", pass_direction: "left", own_pass: ["QS", "AH", "KH"], passed_seats: [0, 1, 2, 3], received_cards: ["4D"], hand: ["2C", "4D"] })
    expect(framesFor(away ?? null, dealt, false)).toEqual([expect.objectContaining({ state: dealt, passTo: null, hold: 0 })])
  })

  test("a new runde starts fresh", () => {
    const shown = first(state({ current_trick: plays("2C") }))
    const next = state({ phase: "passing", last_trick: plays("2C", "5C", "9C", "KC") }, { round_number: 2 })
    expect(framesFor(shown, next, false)).toHaveLength(1)
  })
})
