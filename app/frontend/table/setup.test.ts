import assert from "node:assert/strict"
import { describe, test } from "node:test"
import type { LobbySeat, LobbyTable } from "~/lobby/messages"
import { canStart, centreLine, positionOf, seatAt, seatOf, seatRoles, setupStatus } from "./setup.ts"

const human = (seat: number, name: string, user_id: number): LobbySeat => ({ seat, name, user_id, bot: false })
const bot = (seat: number, name: string): LobbySeat => ({ seat, name, user_id: null, bot: true })
const free = (seat: number): LobbySeat => ({ seat, name: null, user_id: null, bot: false })

const table = (seats: LobbySeat[], over: Partial<LobbyTable> = {}): LobbyTable => ({
  id: 7,
  kind: "open",
  host: "Anders",
  host_id: 1,
  status: "waiting",
  rules: { end_score: 100, queen_breaks_hearts: false, jack_of_diamonds_minus_ten: false, shooters_choice: false },
  seats,
  ...over,
})

describe("where the seats are drawn", () => {
  test("you sit south and the others clockwise from you", () => {
    const bord = table([human(0, "Anders", 1), free(1), human(2, "Bent", 2), bot(3, "Bot 1")])
    assert.equal(seatOf(bord, 2), 2)
    assert.deepEqual([0, 1, 2, 3].map((seat) => positionOf(seat, 2)), ["north", "east", "south", "west"])
    assert.equal(seatAt(bord, "west", 2)?.name, "Bot 1")
  })

  test("a visitor looks from seat 0", () => {
    const bord = table([human(0, "Anders", 1), free(1), free(2), free(3)])
    assert.equal(seatOf(bord, 9), null)
    assert.equal(seatAt(bord, "south", null)?.name, "Anders")
  })
})

describe("before the start", () => {
  test("the vært may start only once every seat holds a human or a bot", () => {
    assert.equal(canStart(table([human(0, "Anders", 1), free(1), bot(2, "Bot 1"), bot(3, "Bot 2")])), false)
    assert.equal(canStart(table([human(0, "Anders", 1), human(1, "Bent", 2), bot(2, "Bot 1"), bot(3, "Bot 2")])), true)
  })

  test("the status says what is missing and who starts", () => {
    const bord = table([human(0, "Anders", 1), human(1, "Bent", 2), free(2), free(3)])
    assert.equal(centreLine(bord), "Venter på 2 spillere")
    assert.match(setupStatus(bord, 1), /^Der mangler 2 spillere\. Inviter nogen/)
    assert.match(setupStatus(bord, 2), /Anders starter spillet/)
    assert.equal(setupStatus(bord, 9), "Vælg en ledig plads for at sætte dig ved bordet.")
  })

  test("each seat says what it is to you", () => {
    const bord = table([human(0, "Anders", 1), bot(1, "Bot 1"), free(2), human(3, "Bent", 2)])
    assert.deepEqual(bord.seats.map((seat) => seatRoles(seat, bord, 1)), [["vært", "dig"], ["bot"], [], []])
  })
})
