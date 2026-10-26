import assert from "node:assert/strict"
import { describe, test } from "node:test"
import { FACE_DOWN, fordaektLabel, fordaektOffer, fordaektWaiting, isFaceDown } from "./fordaekt.ts"
import type { FordaektView, PlayView } from "./messages"

const names = { me: 0, names: ["Anders", "Bent", "Carla", "Dennis"] }
const laid = (over: Partial<FordaektView> = {}): FordaektView => ({ seat: 1, card: null, waiting: true, turned: false, ...over })

describe("fordækt", () => {
  test("the face-down code is no card", () => {
    assert.equal(isFaceDown(FACE_DOWN), true)
    assert.equal(isFaceDown("9C"), false)
  })

  test("the label says whose card it is and which suit it counts as", () => {
    assert.equal(fordaektLabel(laid(), "D", names), "Bent: fordækt · gælder som ruder")
    assert.equal(fordaektLabel(laid({ seat: 0, card: "9C" }), "D", names), "Dit fordækte kort · gælder som ruder")
  })

  test("the card lies on the table only until it is played", () => {
    const play = (fordaekt: FordaektView | null) => ({ fordaekt }) as PlayView
    assert.deepEqual(fordaektWaiting(play(laid())), laid())
    assert.equal(fordaektWaiting(play(laid({ waiting: false, turned: true }))), null)
    assert.equal(fordaektWaiting(play(null)), null)
    assert.equal(fordaektWaiting(null), null)
  })

  test("the melder is told what fordækt does", () => {
    assert.match(fordaektOffer("D").detail, /ingen ruder efter byttet/)
  })
})
