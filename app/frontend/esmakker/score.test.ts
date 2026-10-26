import assert from "node:assert/strict"
import { describe, test } from "node:test"
import type { EsmakkerPoints, ScoreRow } from "./messages"
import { lookupCell, lookupNotes, lookupTable, sheetRows, signedPoints, standing, totalPoints } from "./score.ts"

const STANDARD: EsmakkerPoints = {
  stakes: { "8": 1, "9": 1.5, "10": 2, "11": 2.5, "12": 3, "13": 3.5 },
  pahaeng: 2,
  trumflos: 2,
  klor: 2,
  vip_first: 2,
  vip_second: 4,
  vip_third: 8,
  bank: 2,
  sol: 3,
  ren_sol: 4,
  bordlaegger: 5,
  ren_bordlaegger: 6,
}

// REGLER §2.0 "Opslagstabel", cell by cell as printed there.
const REGLER = `
8 | 1 | 2 | 3 | 4 | 5 | 6
8p | 2 | 4 | 6 | 8 | 10 | 12
9 | 1,5 | 2,5 | 3,5 | 4,5 | 5,5 | –
9p | 3 | 5 | 7 | 9 | 11 | –
Sol | 3 | – | – | – | – | –
10 | 2 | 3 | 4 | 5 | – | –
10p | 4 | 6 | 8 | 10 | – | –
Ren sol | 4 | – | – | – | – | –
11 | 2,5 | 3,5 | 4,5 | – | – | –
11p | 5 | 7 | 9 | – | – | –
Bordlægger | 5 | – | – | – | – | –
12 | 3 | 4 | – | – | – | –
12p | 6 | 8 | – | – | – | –
Ren bordlægger | 6 | – | – | – | – | –
13 | 3,5 | – | – | – | – | –
13p | 7 | – | – | – | – | –`

describe("the lookup table", () => {
  test("at the default values it is REGLER's table, every row and cell", () => {
    const printed = lookupTable(STANDARD).map((row) => [row.label, ...row.cells.map(lookupCell)].join(" | "))
    assert.deepEqual(printed, REGLER.trim().split("\n"))
  })

  test("it is built from the bord's own point values", () => {
    const rows = lookupTable({ ...STANDARD, stakes: { ...STANDARD.stakes, "8": 2 }, pahaeng: 3, sol: 3.5 })
    assert.deepEqual(rows[0]?.cells, [2, 3, 4, 5, 6, 7])
    assert.deepEqual(rows[1]?.cells, [6, 9, 12, 15, 18, 21])
    assert.deepEqual(rows.find((row) => row.label === "Sol")?.cells, [3.5, null, null, null, null, null])
  })

  test("odd amounts are rounded to hundredths, not shown with float noise", () => {
    const rows = lookupTable({ ...STANDARD, stakes: { ...STANDARD.stakes, "8": 0.1 }, pahaeng: 3 })
    assert.deepEqual(rows[1]?.cells.slice(0, 2), [0.3, 3.3])
  })

  test("the notes name the bord's doublings and how bet is paid", () => {
    const notes = lookupNotes({ ...STANDARD, trumflos: 3, bank: 1.5 }).join(" ")
    assert.match(notes, /trumfløs ×3/)
    assert.match(notes, /hvert bank ×1,5/)
    assert.match(notes, /klør som trumf ved vip og halve ×2 \(ikke ved en almindelig melding\)/)
    assert.match(notes, /3\. kort ×8/)
    assert.match(notes, /Bet: indsatsen/)
  })
})

describe("points in words", () => {
  test("signed runde points and totals in Danish", () => {
    assert.deepEqual([4, -1.5, 0, 0.1 + 0.2].map(signedPoints), ["+4", "−1,5", "0", "+0,3"])
    assert.deepEqual([4, -1.5, 0].map(totalPoints), ["4", "−1,5", "0"])
  })

  test("the standing: highest total first, ties share a place", () => {
    const lines = standing([-4, 6, -4, 2], ["Anders", "Bent", "Carla", "Dennis"])
    assert.deepEqual(
      lines.map((line) => [line.name, line.place]),
      [
        ["Bent", 1],
        ["Dennis", 2],
        ["Anders", 3],
        ["Carla", 3],
      ],
    )
  })

  test("the score sheet: each runde with its points and the totals after it", () => {
    const result: ScoreRow = {
      kind: "played",
      melder: 1,
      melding: "9gode",
      trump: "C",
      called_ace: "H",
      esmakker: 3,
      selvmakker: false,
      tricks_won: [2, 6, 1, 4],
      stik: 10,
      gik_hjem: true,
      vip_card: null,
      banks: 0,
      points: [-5, 5, -5, 5],
      totals: [-5, 5, -5, 5],
    }
    const [row] = sheetRows([result], ["Anders", "Bent", "Carla", "Dennis"])
    assert.equal(row?.melder, "Bent")
    assert.equal(row?.makker, "Dennis")
    assert.equal(row?.outcome, "Hjem")
    assert.deepEqual([row?.points, row?.totals], [result.points, result.totals])
  })
})
