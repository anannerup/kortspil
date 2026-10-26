import assert from "node:assert/strict"
import { test } from "node:test"
import type { EsmakkerThought } from "./messages"
import { esmakkerThoughtLine } from "./visKort.ts"

const unknown: EsmakkerThought["expect"] = { melding: null, stik: { self: null, makker: null }, makker: null, points: null }
const nameOf = (seat: number) => `Bot ${seat}`

test("Vis kort: the first bot melder 9, says pas when 9 is not legal, and otherwise chooses at random; it knows no estimates yet", () => {
  assert.equal(
    esmakkerThoughtLine({ decision: "bid", reason: "fixed_melding", melding: "9", expect: { ...unknown, melding: "9" } }, nameOf),
    "Melder 9 — melding 9 · stik — (makker —) · makker — · point —",
  )
  assert.equal(esmakkerThoughtLine({ decision: "pas", reason: "not_legal", melding: "9", expect: unknown }, nameOf), "Pas (9 er ikke lovlig) — melding — · stik — (makker —) · makker — · point —")
  assert.equal(esmakkerThoughtLine({ decision: "play", reason: "random", melding: null, expect: unknown }, nameOf), "Tilfældigt lovligt kort — melding — · stik — (makker —) · makker — · point —")
})

test("Vis kort: a later bot's estimates fill in", () => {
  const expect = { melding: "10halve", stik: { self: 6, makker: 4 }, makker: 2, points: 3.5 }
  assert.equal(
    esmakkerThoughtLine({ decision: "bid", reason: "fixed_melding", melding: "10halve", expect }, nameOf),
    "Melder 10 halve — melding 10 halve · stik 6 (makker 4) · makker Bot 2 · point +3,5",
  )
})
