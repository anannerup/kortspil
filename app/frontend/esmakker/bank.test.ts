import assert from "node:assert/strict"
import { describe, test } from "node:test"
import { bankButtonLabel, bankFactor, bankLines, bankSecondsLeft, banksNote, countdownFraction, countdownSeconds } from "./bank.ts"
import type { BankWindow } from "./messages"

const window: BankWindow = { seconds: 8, seconds_left: 8, closes_at: "2026-10-26T12:00:08.000Z" }
const names = { me: 0, names: ["Anders", "Bent", "Carla", "Dennis"] }

describe("the bank window's countdown", () => {
  test("counts down from when the state arrived, never below 0; none without a window", () => {
    assert.equal(bankSecondsLeft(window, 1000, 1000), 8)
    assert.equal(bankSecondsLeft(window, 1000, 3500), 5.5)
    assert.equal(bankSecondsLeft({ ...window, seconds_left: 2 }, 0, 5000), 0)
    assert.equal(bankSecondsLeft(null, 0, 0), null)
  })

  test("shows whole seconds rounded up, and the share left for the bar", () => {
    assert.deepEqual([8, 5.5, 0.2, 0, -1].map(countdownSeconds), [8, 6, 1, 0, 0])
    assert.equal(countdownFraction(4, window), 0.5)
    assert.equal(countdownFraction(9, window), 1)
    assert.equal(countdownFraction(-1, window), 0)
  })
})

describe("the banks", () => {
  test("each doubles by the bord's factor", () => {
    assert.deepEqual([0, 1, 2].map((banks) => bankFactor(banks)), ["", "×2", "×4"])
    assert.equal(bankFactor(2, 3), "×9")
    assert.equal(bankFactor(1, 1.5), "×1,5")
  })

  test("the button: the first bank, then the melder's answer", () => {
    assert.equal(bankButtonLabel(0), "Bank (×2)")
    assert.equal(bankButtonLabel(1), "Bank igen (×4)")
  })

  test("who banked, in order, and the score sheet's note", () => {
    assert.deepEqual(bankLines([2, 0], names), ["Carla bankede ×2", "Du bankede igen ×4"])
    assert.deepEqual(bankLines([], names), [])
    assert.deepEqual([0, 1, 2].map(banksNote), ["", "1 bank", "2 bank"])
  })
})
