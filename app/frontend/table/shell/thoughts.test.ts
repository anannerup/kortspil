import { test } from "node:test"
import assert from "node:assert/strict"
import type { BotThought, VisKort } from "../messages"
import { logThoughts, revealedHand, type LoggedThought } from "./thoughts.ts"

type Thought = { text: string }
const thought = (text: string, version: number, round_number = 1): BotThought<Thought> => ({ text, version, round_number })
const shown = (...bots: [number, BotThought<Thought> | null][]): VisKort<Thought> => ({
  on: true,
  bots: bots.map(([seat, botThought]) => ({ seat, hand: [`${seat + 2}C`], thought: botThought })),
})

test("a bot's hand shows only while Vis kort is on", () => {
  assert.deepEqual(revealedHand(shown([1, null]), 1), ["3C"])
  assert.equal(revealedHand(shown([1, null]), 2), null)
  assert.equal(revealedHand({ on: false, bots: [] }, 1), null)
  assert.equal(revealedHand(null, 1), null)
})

test("the log adds each new thought once, newest first", () => {
  let log: LoggedThought<Thought>[] = []
  log = logThoughts(log, shown([1, thought("a", 0)], [2, null]), 1)
  log = logThoughts(log, shown([1, thought("a", 0)], [2, thought("b", 1)]), 1)
  log = logThoughts(log, shown([1, thought("a", 0)], [2, thought("b", 1)]), 1)

  assert.deepEqual(log.map((entry) => [entry.seat, entry.thought.text]), [[2, "b"], [1, "a"]])
})

test("a new runde starts an empty log and leaves out thoughts from the runde before", () => {
  const before = logThoughts([], shown([1, thought("a", 0)]), 1)

  assert.deepEqual(logThoughts(before, shown([1, thought("a", 0)], [2, thought("c", 60, 2)]), 2).map((entry) => entry.thought.text), ["c"])
})

test("switched off, the log empties", () => {
  const before = logThoughts([], shown([1, thought("a", 0)]), 1)

  assert.deepEqual(logThoughts(before, { on: false, bots: [] }, 1), [])
  assert.deepEqual(logThoughts(before, null, 1), [])
})
