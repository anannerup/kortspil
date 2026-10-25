import assert from "node:assert/strict"
import { test } from "node:test"
import { botKind, seatLabel } from "./texts.ts"

test("a bot is named with its level, a player by name", () => {
  assert.equal(seatLabel({ name: "Bot 2", bot: true, bot_level: "svaer" }), "Bot 2 · Svær")
  assert.equal(seatLabel({ name: "Alma", bot: false, bot_level: null }), "Alma")
  assert.equal(botKind("mellem"), "Bot · Mellem")
})

test("a bot that took over is Bot · Let (overtog fra …)", () => {
  assert.equal(seatLabel({ name: "Bot 3", bot: true, bot_level: "let", took_over_from: "Anders" }), "Bot · Let (overtog fra Anders)")
})
