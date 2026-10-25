import assert from "node:assert/strict"
import { describe, test } from "node:test"
import type { BiddingEntry, BiddingOutcome, BiddingView } from "./messages"
import { biddingHeadline, historyLabel, ladderRows, lastSaid, meldingLabel, turnText } from "./bidding.ts"

const names = { me: 0, names: ["Anders", "Alma", "Bent", "Carla"] }

const bidding = (over: Partial<BiddingView>): BiddingView => ({
  phase: "bidding",
  forhand: 1,
  dealer: 0,
  to_act: 1,
  melding: null,
  holder: null,
  serveret: null,
  passed: [],
  went_with: [],
  history: [],
  outcome: null,
  ...over,
})

describe("the meldingsrunde in words", () => {
  test("meldinger by their Danish names", () => {
    assert.equal(meldingLabel("9"), "9")
    assert.equal(meldingLabel("10halve"), "10 halve")
    assert.equal(meldingLabel("13vip"), "13 vip")
    assert.equal(meldingLabel("ren_bordlaegger"), "ren bordlægger")
  })

  test("the offered meldinger as a grid: a row per number, påhæng in the bord's order, each sol-melding on its own row", () => {
    const order = ["vip", "halve", "gode"]
    assert.deepEqual(ladderRows(["9vip", "sol", "10", "10gode", "10halve", "10vip", "ren_sol"], order), [
      { number: "9", cells: [{ code: "9vip", text: "vip", column: 4 }] },
      { number: null, cells: [{ code: "sol", text: "sol", column: 1 }] },
      {
        number: "10",
        cells: [
          { code: "10", text: "10", column: 1 },
          { code: "10gode", text: "gode", column: 2 },
          { code: "10halve", text: "halve", column: 3 },
          { code: "10vip", text: "vip", column: 4 },
        ],
      },
      { number: null, cells: [{ code: "ren_sol", text: "ren sol", column: 1 }] },
    ])
    assert.deepEqual(ladderRows(["11vip", "11halve"], ["halve", "vip", "gode"]), [
      { number: "11", cells: [{ code: "11vip", text: "vip", column: 3 }, { code: "11halve", text: "halve", column: 4 }] },
    ])
    assert.deepEqual(ladderRows([], order), [])
  })

  test("the history and what each seat said last", () => {
    const history: BiddingEntry[] = [
      { seat: 1, action: "bid", melding: "9" },
      { seat: 2, action: "bid", melding: "10" },
      { seat: 1, action: "det_kan_jeg_selv", melding: "10" },
      { seat: 2, action: "pas", melding: "10" },
    ]
    assert.deepEqual(history.map(historyLabel), ["9", "10", "det kan jeg selv (10)", "pas"])
    assert.deepEqual([...lastSaid(history)], [[1, "det kan jeg selv"], [2, "pas"]])
  })

  test("whose turn and what they may do", () => {
    assert.equal(turnText(bidding({ to_act: 0 }), names), "Din tur: meld eller sig pas.")
    assert.equal(turnText(bidding({ to_act: 2, melding: "9", holder: 1 }), names), "Bent skal melde højere eller sige pas.")
    assert.equal(turnText(bidding({ to_act: 0, melding: "10", holder: 2, serveret: 0 }), names), 'Din tur: sig "det kan jeg selv" (10) eller pas.')
    assert.equal(turnText(bidding({ to_act: 1, melding: "sol", holder: 2, serveret: 1 }), names), 'Alma kan sige "det kan jeg selv" (sol) eller pas.')
  })

  test("the melding standing, and the ending", () => {
    assert.deepEqual(biddingHeadline(bidding({}), names), { headline: "Ingen melding endnu", detail: null })
    assert.deepEqual(biddingHeadline(bidding({ melding: "9vip", holder: 0 }), names), { headline: "9 vip", detail: "Du har meldingen" })
    assert.deepEqual(biddingHeadline(bidding({ melding: "sol", holder: 3, went_with: [1, 0] }), names), { headline: "sol", detail: "Carla har meldingen · går med: Alma og dig" })

    const melder: BiddingOutcome = { kind: "melder", melder: 1, melding: "10halve", went_with: [], reason: null, dealer: null }
    assert.deepEqual(biddingHeadline(bidding({ phase: "complete", to_act: null, outcome: melder }), names), { headline: "Melder: Alma — 10 halve", detail: "Trumf og es kommer." })
    assert.equal(biddingHeadline(bidding({ outcome: { ...melder, melder: 0 } }), names).headline, "Du er melder — 10 halve")
    assert.equal(turnText(bidding({ phase: "complete", to_act: null, outcome: melder }), names), null)

    const allPassed: BiddingOutcome = { kind: "redeal", melder: null, melding: null, went_with: [], reason: "all_passed", dealer: 1 }
    assert.deepEqual(biddingHeadline(bidding({ outcome: allPassed }), names), { headline: "Alle sagde pas", detail: "Kortene gives om. Alma giver." })

    const jernhaand: BiddingOutcome = { kind: "redeal", melder: null, melding: null, went_with: [], reason: "jernhaand", dealer: 0 }
    const claimed = bidding({ outcome: jernhaand, history: [{ seat: 2, action: "jernhaand", melding: null }] })
    assert.deepEqual(biddingHeadline(claimed, names), { headline: "Jernhånd", detail: "Bent har jernhånd. Kortene gives om, og du giver igen." })
  })
})
