import assert from "node:assert/strict"
import { describe, test } from "node:test"
import type { EsmakkerView, RundeResultView, SolPlayView } from "./messages"
import { contractText, declarationText, overviewRows, resultText, roleOf } from "./play.ts"
import { discardButtonText, discardSize, solAllowedText, solPlayersText, solStatus } from "./sol.ts"

const names = { me: 0, names: ["Anders", "Bent", "Carla", "Dennis"] }

const sol = (over: Partial<SolPlayView> = {}): SolPlayView => ({
  kind: "sol",
  trump: null,
  called_ace: null,
  esmakker: null,
  selvmakker: false,
  side_stik: null,
  fordaekt: null,
  turned: [],
  vip_card: null,
  bank_window: false,
  banks: [],
  players: [1, 2],
  most_stik: 1,
  vaeltet: [],
  exchange_order: [1, 2, 3, 0],
  exchanging: null,
  discard_size: 0,
  kitty_cards: [],
  discarded: [],
  current_trick: [],
  last_trick: [],
  last_trick_winner: null,
  tricks_won: [0, 0, 0, 0],
  legal_moves: [],
  ...over,
})

const view = (play: SolPlayView, over: Partial<EsmakkerView> = {}): EsmakkerView => ({
  seat: 0,
  phase: "playing",
  hand: ["AC", "2C"],
  card_counts: { "1": 13, "2": 13, "3": 13 },
  kitty_count: 0,
  dealer: 0,
  forhand: 1,
  to_act: 1,
  bidding: {
    phase: "complete",
    forhand: 1,
    dealer: 0,
    to_act: null,
    melding: "sol",
    holder: 1,
    serveret: null,
    passed: [3, 0],
    went_with: [2],
    history: [],
    outcome: { kind: "melder", melder: 1, melding: "sol", went_with: [2], reason: null, dealer: null },
  },
  choices: { meldinger: [], det_kan_jeg_selv: false, gaa_med: false, pas: false, jernhaand: false, trumps: [], aces: [], turn_card: false, accept_trump: false, bank: false, discard: false, fordaekt: [] },
  play,
  result: null,
  ...over,
})

const result = (over: Partial<RundeResultView> = {}): RundeResultView => ({
  kind: "sol",
  melder: 1,
  melding: "sol",
  trump: null,
  called_ace: null,
  esmakker: null,
  selvmakker: false,
  tricks_won: [6, 1, 2, 4],
  stik: 1,
  gik_hjem: true,
  vip_card: null,
  banks: 0,
  points: [0, 6, -6, 0],
  sol: { players: [1, 2], most_stik: 1, vaeltet: [2] },
  ...over,
})

describe("the kitty going round", () => {
  test("the seat exchanging is told how many cards it holds of the kitty; the others whose turn it is", () => {
    const exchanging = sol({ exchanging: 2, discard_size: 2 })
    assert.deepEqual(declarationText(view(exchanging, { phase: "exchanging", to_act: 2 }), names), {
      headline: "Melder: Bent — sol",
      detail: "Carla bytter med katten (2 kort) …",
    })
    const mine = declarationText(view(sol({ exchanging: 0, discard_size: 3 }), { phase: "exchanging", to_act: 0 }), names)
    assert.equal(mine?.detail, "Du har taget katten op. Læg 3 kort væk, eller læg kattens kort tilbage og behold dine egne.")
    const last = declarationText(view(sol({ exchanging: 0, discard_size: 1 }), { phase: "exchanging", to_act: 0 }), names)
    assert.equal(last?.detail, "Du har taget kattens sidste 1 kort op. Læg 1 kort væk, eller læg kattens kort tilbage og behold dine egne.")
  })

  test("how many cards to pick, and the button", () => {
    assert.equal(discardSize(view(sol({ exchanging: 0, discard_size: 2 }))), 2)
    assert.equal(discardButtonText(1, 2), "Læg 1 af 2 kort væk")
    assert.equal(discardButtonText(2, 2), "Læg de 2 kort væk")
    assert.equal(discardButtonText(3, 3), "Læg de 3 kort væk")
  })

  test("who plays the sol-melding", () => {
    assert.equal(solPlayersText(sol(), "sol", names), "Bent spiller sol, Carla går med")
    assert.equal(solPlayersText(sol({ players: [1, 2, 0] }), "ren_sol", names), "Bent spiller ren sol, Carla og du går med")
    assert.equal(solPlayersText(sol({ players: [0] }), "sol", names), "Du spiller sol")
  })
})

describe("the stik at a sol-melding", () => {
  test("no trump, the ace lowest; each sol player's role, stik and væltet", () => {
    const play = sol({ tricks_won: [3, 1, 2, 0], vaeltet: [2] })
    assert.equal(contractText(view(play)), "sol · ingen trumf · es lavest")
    assert.deepEqual([0, 1, 2, 3].map((seat) => roleOf(seat, view(play))), [null, "melder", "går med · væltet", null])
    assert.deepEqual(solStatus(play, names), [
      { seat: 1, name: "Bent", stik: 1, vaeltet: false },
      { seat: 2, name: "Carla", stik: 2, vaeltet: true },
    ])
    assert.equal(solAllowedText(1), "Højst ét stik")
    assert.equal(solAllowedText(0), "Ingen stik")
  })
})

describe("the result of a sol runde", () => {
  test("each sol player klaret or væltet", () => {
    assert.deepEqual(resultText(result(), names), {
      headline: "Sol: 1 klaret, 1 væltet",
      detail: "Bent tog 1 stik og klarede den. Carla tog 2 stik og er væltet.",
    })
    assert.equal(resultText(result({ sol: { players: [1], most_stik: 0, vaeltet: [] }, melding: "ren_sol", tricks_won: [5, 0, 4, 4] }), names).headline, "Ren sol klaret")
  })

  test("a runde stopped once every sol player was væltet says so", () => {
    const stopped = result({ tricks_won: [0, 2, 0, 0], sol: { players: [1], most_stik: 1, vaeltet: [1] }, points: [3, -9, 3, 3] })
    assert.deepEqual(resultText(stopped, names), {
      headline: "Sol væltet",
      detail: "Bent tog 2 stik og er væltet. Alle sol-spillere var væltet, så runden stoppede efter 2 stik.",
    })
  })

  test("on the score sheet: the sol players, their stik and how it went", () => {
    const [row] = overviewRows([result()], names.names)
    assert.deepEqual(row && { melder: row.melder, makker: row.makker, trump: row.trump, ace: row.ace, stik: row.stik, outcome: row.outcome }, {
      melder: "Bent + Carla",
      makker: "–",
      trump: "–",
      ace: "–",
      stik: "1 · 2",
      outcome: "1 klaret",
    })
  })
})
