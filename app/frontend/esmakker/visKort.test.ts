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

test("Vis kort: Svær's reasons in words, with its estimates", () => {
  const expect = { melding: "10", stik: { self: 6.5, makker: 2 }, makker: null, points: 1.25 }
  assert.equal(
    esmakkerThoughtLine({ decision: "bid", reason: "bid_lowest", melding: "10", expect }, nameOf),
    "Melder 10: laveste trin med bedst forventet gevinst — melding 10 · stik 6,5 (makker 2) · makker — · point +1,25",
  )
  assert.equal(
    esmakkerThoughtLine({ decision: "play", reason: "afkast_renonce", melding: null, expect: { ...expect, makker: 3 } }, nameOf),
    "Smider fra farven, den vil være renonce i — melding 10 · stik 6,5 (makker 2) · makker Bot 3 · point +1,25",
  )
  assert.equal(esmakkerThoughtLine({ decision: "pas", reason: "pas_weak", melding: null, expect: unknown }, nameOf), "Pas: for svag til 8 og ingen sol — melding — · stik — (makker —) · makker — · point —")
  assert.equal(esmakkerThoughtLine({ decision: "gaa_med", reason: "sol_test", melding: "sol", expect: unknown }, nameOf).split(" — ")[0], "Sol-testen holder til sol")
})
