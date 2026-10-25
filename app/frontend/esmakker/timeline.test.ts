import assert from "node:assert/strict"
import { describe, test } from "node:test"
import { FLY_MS, PAUSE_MS, SWEEP_MS } from "../table/timeline.ts"
import type { EsmakkerTableState, PlayView } from "./messages"
import { esmakkerFrames } from "./timeline.ts"

let version = 0
const state = (playOver: Partial<PlayView> | null, over: Partial<EsmakkerTableState> = {}): EsmakkerTableState =>
  ({
    table_id: 1,
    table_kind: "open",
    game: "esmakker",
    game_id: 1,
    status: "in_progress",
    round_number: 1,
    runder: 10,
    runde: 1,
    version: ++version,
    seats: [],
    score: { totals: [0, 0, 0, 0], results: [] },
    timer: { warning: 30, limit: 60 },
    view: {
      seat: 0,
      phase: "playing",
      hand: ["2C"],
      to_act: 1,
      result: null,
      play:
        playOver === null
          ? null
          : {
              trump: "H",
              called_ace: "D",
              esmakker: null,
              selvmakker: false,
              kitty_cards: [],
              discarded: [],
              current_trick: [],
              last_trick: [],
              last_trick_winner: null,
              tricks_won: [0, 0, 0, 0],
              side_stik: null,
              legal_moves: [],
              ...playOver,
            },
    },
    ...over,
  }) as unknown as EsmakkerTableState

const settle = (next: EsmakkerTableState) => esmakkerFrames(null, next, false)[0]!

describe("the es-makker timeline", () => {
  test("before the play there is nothing to pace", () => {
    const first = settle(state(null))
    assert.deepEqual(esmakkerFrames(first, state(null), false).map((frame) => frame.hold), [0])
  })

  test("a played card is held while it flies in", () => {
    const shown = settle(state({}))
    const frames = esmakkerFrames(shown, state({ current_trick: [{ seat: 0, card: "2C" }] }), false)
    assert.equal(frames.length, 1)
    assert.ok(frames[0]!.hold > 0)
  })

  test("a completed stik rests, sweeps to its winner, then the table settles", () => {
    const shown = settle(state({ current_trick: [{ seat: 0, card: "2C" }, { seat: 1, card: "3C" }, { seat: 2, card: "4C" }], tricks_won: [0, 0, 0, 0] }))
    const done = [{ seat: 0, card: "2C" }, { seat: 1, card: "3C" }, { seat: 2, card: "4C" }, { seat: 3, card: "AC" }]
    const next = state({ last_trick: done, last_trick_winner: 3, tricks_won: [0, 0, 0, 1] }, { status: "finished", next_path: "/borde/9" })
    const frames = esmakkerFrames(shown, next, false)

    assert.deepEqual(frames.map((frame) => frame.hold), [FLY_MS + PAUSE_MS, SWEEP_MS, 0])
    assert.deepEqual(frames.map((frame) => frame.sweepTo), [null, 3, null])
    assert.deepEqual(frames[0]!.trick, done)
    assert.deepEqual(frames[0]!.state.view.play?.tricks_won, [0, 0, 0, 0], "the stik counts change once it is swept")
    assert.equal(frames[0]!.state.status, "in_progress", "the end shows after the last stik")
    assert.equal(frames[0]!.state.next_path, undefined)
    assert.equal(frames[2]!.state, next)
  })

  test("with reduced motion the stik settles at once", () => {
    const shown = settle(state({}))
    const next = state({ last_trick: [{ seat: 0, card: "2C" }], last_trick_winner: 0 })
    assert.equal(esmakkerFrames(shown, next, true).length, 1)
  })
})
