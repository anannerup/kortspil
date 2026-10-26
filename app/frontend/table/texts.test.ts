import assert from "node:assert/strict"
import { test } from "node:test"
import { botKind, hjerterfriThoughtLine, seatLabel } from "./texts.ts"

test("a bot is named with its level, a player by name", () => {
  assert.equal(seatLabel({ name: "Bot 2", bot: true, bot_level: "svaer" }), "Bot 2 · Svær")
  assert.equal(seatLabel({ name: "Alma", bot: false, bot_level: null }), "Alma")
  assert.equal(botKind("mellem"), "Bot · Mellem")
})

test("a bot that took over is Bot · Let (overtog fra …)", () => {
  assert.equal(seatLabel({ name: "Bot 3", bot: true, bot_level: "let", took_over_from: "Anders" }), "Bot · Let (overtog fra Anders)")
})

test("Vis kort: a hjerterfri bot's decision and the rule behind it in one line", () => {
  assert.equal(hjerterfriThoughtLine({ decision: "play", choice: "QS", reason: "queen_discard" }), "Spiller spar dame: smider spar dame")
  assert.equal(hjerterfriThoughtLine({ decision: "pass", choice: ["QS", "AH", "TD"], reason: "let_pass" }), "Giver spar dame, hjerter es, ruder 10: farlige kort væk: spar dame, høje spar, høje hjerter")
  assert.equal(hjerterfriThoughtLine({ decision: "moon", choice: "add_to_others", reason: "moon_hurry_end" }), "26 til de andre: fører og vil slutte spillet")
})
