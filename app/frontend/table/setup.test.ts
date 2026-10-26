import assert from "node:assert/strict"
import { describe, test } from "node:test"
import type { EsmakkerLobbyTable, HjerterfriLobbyTable, LobbyNudge, LobbySeat } from "~/lobby/messages"
import { canStart, centreLine, lengthLabel, freeForNudge, friendStatus, positionOf, seatAt, seatOf, seatRoles, setupStatus } from "./setup.ts"

const human = (seat: number, name: string, user_id: number): LobbySeat => ({ seat, name, user_id, bot: false, bot_level: null })
const bot = (seat: number, name: string): LobbySeat => ({ seat, name, user_id: null, bot: true, bot_level: "mellem" })
const free = (seat: number): LobbySeat => ({ seat, name: null, user_id: null, bot: false, bot_level: null })

const table = (seats: LobbySeat[], over: Partial<HjerterfriLobbyTable> = {}): HjerterfriLobbyTable => ({
  id: "babc",
  name: "Anders' bord",
  path: "/borde/babc",
  game: "hjerterfri",
  nudges: [],
  reserved: 0,
  kind: "open",
  host: "Anders",
  host_id: 1,
  status: "waiting",
  rules: { end_score: 100, queen_breaks_hearts: false, jack_of_diamonds_minus_ten: false, shooters_choice: false },
  runder: null,
  bots_allowed: true,
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

describe("an es-makker bord", () => {
  const esmakker = (seats: LobbySeat[]): EsmakkerLobbyTable => {
    const { rules: _rules, game: _game, ...rest } = table(seats)
    return {
      ...rest,
      game: "esmakker",
      runder: 10,
      bots_allowed: false,
      rules: {
        pahaeng_order: ["vip", "halve", "gode"],
        joker_trumpable: false,
        esmakker_banks_first: true,
        bank_window: 8,
        points: { stakes: { "8": 1, "9": 1.5, "10": 2, "11": 2.5, "12": 3, "13": 3.5 }, pahaeng: 2, trumflos: 2, klor: 2, vip_first: 2, vip_second: 4, vip_third: 8, bank: 2, sol: 3, ren_sol: 4, bordlaegger: 5, ren_bordlaegger: 6 },
      },
    }
  }

  test("starts only with four humans, and counts runder instead of points", () => {
    assert.equal(canStart(esmakker([human(0, "Anders", 1), human(1, "Bent", 2), human(2, "Carla", 3), bot(3, "Bot 1")])), false)
    assert.equal(canStart(esmakker([human(0, "Anders", 1), human(1, "Bent", 2), human(2, "Carla", 3), human(3, "Dennis", 4)])), true)
    assert.equal(lengthLabel(esmakker([])), "10 runder")
    assert.equal(lengthLabel(table([])), "Til 100 point")
  })

  test("the vært is not told to add bots", () => {
    const bord = esmakker([human(0, "Anders", 1), human(1, "Bent", 2), free(2), free(3)])
    assert.equal(setupStatus(bord, 1), "Der mangler 2 spillere. Inviter nogen; es-makker spilles af fire spillere.")
  })
})

describe("puf", () => {
  const nudge = (user_id: number, state: LobbyNudge["state"], from_id = 1): LobbyNudge => ({
    id: user_id,
    user_id,
    name: `Ven ${user_id}`,
    from_id,
    from_name: from_id === 1 ? "Anders" : "Bent",
    state,
    expires_at: "2026-10-25T12:01:00Z",
  })
  const friend = (id: number, online = true) => ({ id, username: `Ven ${id}`, online })

  test("pending pufs hold free seats, so the vært cannot nudge more than there is room for", () => {
    const bord = table([human(0, "Anders", 1), bot(1, "Bot 1"), free(2), free(3)], { nudges: [nudge(5, "pending"), nudge(6, "pending")], reserved: 2 })
    assert.equal(freeForNudge(bord), 0)
    assert.deepEqual(friendStatus(bord, friend(5), 1).label, "Puffet · venter på svar")
    assert.equal(friendStatus(bord, friend(7), 1).canNudge, false)
  })

  test("anyone seated may puf; the sender and the vært may withdraw it, and the others see who sent it", () => {
    const bord = table([human(0, "Anders", 1), human(1, "Bent", 2), human(2, "Cille", 3), free(3)], { nudges: [nudge(5, "pending", 2)], reserved: 1 })
    assert.deepEqual(friendStatus(bord, friend(5), 2), { label: "Puffet · venter på svar", canNudge: false, pending: bord.nudges[0], canWithdraw: true })
    assert.equal(friendStatus(bord, friend(5), 1).canWithdraw, true, "the vært")
    assert.deepEqual(friendStatus(bord, friend(5), 3).label, "Puffet af Bent · venter på svar")
    assert.equal(friendStatus(bord, friend(5), 3).canWithdraw, false)
  })

  test("a declined or expired puf can be sent again, and a seated friend needs none", () => {
    const bord = table([human(0, "Anders", 1), human(1, "Bent", 2), free(2), free(3)], { nudges: [nudge(5, "declined"), nudge(6, "expired"), nudge(2, "accepted")] })
    assert.deepEqual(friendStatus(bord, friend(5), 1), { label: "Sagde nej tak", canNudge: true, pending: null, canWithdraw: false })
    assert.equal(friendStatus(bord, friend(6), 1).label, "Puffet udløb")
    assert.equal(friendStatus(bord, friend(2), 1).label, "Sidder ved bordet")
    assert.equal(friendStatus(bord, friend(8, false), 1).label, "Offline")
  })
})
