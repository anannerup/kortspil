import assert from "node:assert/strict"
import { describe, test } from "node:test"
import type { SeatView, TableState, TrickPlay } from "./messages"
import { FLY_MS, GIVE_MS, PAUSE_MS, SWEEP_MS, TAKE_MS, framesFor, type Frame } from "./timeline.ts"

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
  host_seat: 0,
  timer: { warning: 30, limit: 60 },
  ...rest,
})

const plays = (...codes: string[]): TrickPlay[] => codes.map((card, seat) => ({ seat, card }))
const first = (s: TableState) => framesFor(null, s, false)[0] as Frame

describe("framesFor", () => {
  test("the first state shows as it is", () => {
    const s = state({ current_trick: plays("2C") })
    assert.deepEqual(framesFor(null, s, false), [{ state: s, trick: plays("2C"), sweepTo: null, pass: null, lastTrick: { plays: [], winner: null }, hold: 0 }])
  })

  test("a played card holds until it has landed", () => {
    const shown = first(state({ current_trick: plays("2C") }))
    const [frame] = framesFor(shown, state({ current_trick: plays("2C", "5C") }), false)
    assert.deepEqual(frame?.trick, plays("2C", "5C"))
    assert.equal(frame?.hold, FLY_MS + 60)
  })

  test("a completed stik rests, sweeps to its winner, then the table moves on", () => {
    const shown = first(state({ current_trick: plays("2C", "5C", "9C") }))
    const next = state(
      { current_trick: [], last_trick: plays("2C", "5C", "9C", "KC"), last_trick_winner: 3, to_act: 3, hand: ["3H"] },
      { points_taken: [0, 0, 0, 1] },
    )
    const [resting, leaving, settled] = framesFor(shown, next, false)

    assert.deepEqual(resting?.trick, plays("2C", "5C", "9C", "KC"))
    assert.equal(resting?.sweepTo, null)
    assert.equal(resting?.hold, FLY_MS + PAUSE_MS)
    assert.equal(leaving?.sweepTo, 3)
    assert.equal(leaving?.hold, SWEEP_MS)
    assert.deepEqual(settled, { state: next, trick: [], sweepTo: null, pass: null, lastTrick: { plays: next.view.last_trick, winner: 3 }, hold: 0 })
  })

  test("while the stik lies on the table, points, Sidste stik and the turn wait", () => {
    const earlier = plays("4D", "6D", "8D", "TD")
    const shown = first(state({ current_trick: plays("2C", "5C", "9C"), last_trick: earlier, last_trick_winner: 1 }, { points_taken: [0, 0, 0, 0] }))
    const next = state({ last_trick: plays("2C", "5C", "9C", "QS"), last_trick_winner: 3, to_act: 3, legal_moves: ["3H"] }, { points_taken: [0, 0, 0, 13] })
    for (const frame of framesFor(shown, next, false).slice(0, 2)) {
      assert.deepEqual(frame.state.points_taken, [0, 0, 0, 0])
      assert.deepEqual(frame.lastTrick, { plays: earlier, winner: 1 })
      assert.equal(frame.state.view.to_act, null)
      assert.deepEqual(frame.state.view.legal_moves, [])
      assert.deepEqual(frame.state.view.hand, next.view.hand)
    }
  })

  test("the runde result waits until the last stik has left the table", () => {
    const shown = first(state({ current_trick: plays("2C", "5C", "9C") }))
    const next = state(
      { phase: "complete", last_trick: plays("2C", "5C", "9C", "KC"), last_trick_winner: 3, to_act: null, points: [0, 0, 0, 26] },
      { score: { end_score: 100, rows: [], totals: [0, 0, 0, 26], leaders: [0], winners: [] } },
    )
    const [resting, leaving, settled] = framesFor(shown, next, false)
    assert.equal(resting?.state.view.phase, "playing")
    assert.deepEqual(leaving?.state.score.totals, [0, 0, 0, 0])
    assert.equal(settled?.state.view.phase, "complete")
  })

  test("with reduced motion, a completed stik shows the new state at once", () => {
    const shown = first(state({ current_trick: plays("2C", "5C", "9C") }))
    const next = state({ last_trick: plays("2C", "5C", "9C", "KC"), last_trick_winner: 3 })
    assert.deepEqual(framesFor(shown, next, true), [{ state: next, trick: [], sweepTo: null, pass: null, lastTrick: { plays: next.view.last_trick, winner: 3 }, hold: 0 }])
  })

  const seats = [0, 1, 2, 3].map((seat) => ({ seat, name: `S${seat}`, bot: seat > 0, bot_level: seat > 0 ? ("mellem" as const) : null, took_over_from: null, frakoblet: false, seconds_left: null }))

  test("when the pass is done, every seat gives, then takes its pile up", () => {
    // You pass last: the state before has not seen your pass yet.
    const shown = first(state({ phase: "passing", pass_direction: "right", own_pass: [], passed_seats: [1, 2, 3], hand: ["2C", "3C", "QS", "AH", "KH"] }))
    const next = state(
      { phase: "playing", pass_direction: "right", own_pass: ["QS", "AH", "KH"], passed_seats: [0, 1, 2, 3], received_cards: ["4D"], hand: ["2C", "3C", "4D"] },
      { seats },
    )
    const [give, take, settled] = framesFor(shown, next, false)
    assert.equal(give?.pass, "give")
    assert.equal(give?.state.view.phase, "passing")
    assert.deepEqual(give?.state.view.hand, ["2C", "3C"])
    assert.deepEqual(give?.state.view.own_pass, ["QS", "AH", "KH"])
    assert.deepEqual(give?.state.view.passed_seats, [0, 1, 2, 3])
    assert.ok((give?.hold ?? 0) > GIVE_MS)
    assert.partialDeepStrictEqual(take, { state: next, pass: "take", hold: TAKE_MS })
    assert.partialDeepStrictEqual(settled, { state: next, pass: null })
    assert.equal(framesFor(shown, next, true).length, 1)
  })

  test("the cards are given as soon as every seat has passed, and taken up when dealt", () => {
    const shown = first(state({ phase: "passing", pass_direction: "left", own_pass: [], passed_seats: [1, 2, 3], hand: ["2C", "QS", "AH", "KH"] }))
    const allIn = state({ phase: "passing", pass_direction: "left", own_pass: ["QS", "AH", "KH"], passed_seats: [0, 1, 2, 3], hand: ["2C"] })
    const given = framesFor(shown, allIn, false)
    assert.equal(given.length, 1)
    assert.partialDeepStrictEqual(given[0], { state: allIn, pass: "give" })
    const dealt = state({ phase: "playing", pass_direction: "left", own_pass: ["QS", "AH", "KH"], passed_seats: [0, 1, 2, 3], received_cards: ["4D"], hand: ["2C", "4D"] })
    assert.deepEqual(framesFor(given[0] ?? null, dealt, false).map((frame) => frame.pass), ["take", null])
  })

  test("a new runde starts fresh", () => {
    const shown = first(state({ current_trick: plays("2C") }))
    const next = state({ phase: "passing", last_trick: plays("2C", "5C", "9C", "KC") }, { round_number: 2 })
    assert.equal(framesFor(shown, next, false).length, 1)
  })
})
