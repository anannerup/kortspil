import assert from "node:assert/strict"
import { describe, test } from "node:test"
import type { ServerMessage } from "../messages"
import { leaveConfirmText, routeMessage, routeRefusal } from "./routing.ts"

// The shell routes the envelope; the state is the game's and passes through untouched.
type Some = { game: "any"; version: number }
const route = (message: ServerMessage<Some>) => routeMessage(message)

describe("a bord's messages, the same at every game", () => {
  test("the chat goes to the chat", () => {
    assert.deepEqual(route({ type: "chat_history", messages: [], max_length: 300 }), { kind: "chat" })
    assert.deepEqual(route({ type: "chat_rejected", reason: "too_fast" }), { kind: "chat" })
    assert.deepEqual(
      route({ type: "chat_message", message: { id: 1, user_id: 2, seat: 0, name: "Alma", text: "Hej", at: "2026-10-26T12:00:00Z" } }),
      { kind: "chat" },
    )
  })

  test("a state goes to the game's page as it came", () => {
    const state: Some = { game: "any", version: 7 }
    const routed = route({ type: "state", state })
    assert.equal(routed.kind, "state")
    assert.equal(routed.kind === "state" && routed.state, state)
  })

  test("a closed bord goes to the lobby; a waiting one to its own URL", () => {
    assert.deepEqual(route({ type: "closed" }), { kind: "go", to: "/" })
    assert.deepEqual(route({ type: "waiting", path: "/borde/abc" }), { kind: "go", to: "/borde/abc" })
  })

  test("forladt reloads: the server decides what the bord's URL shows now", () => {
    assert.deepEqual(route({ type: "forladt" }), { kind: "reload" })
  })

  test("the tur-ur's warning shows the whole seconds left", () => {
    assert.deepEqual(route({ type: "turn_warning", seconds_left: 14.6 }), { kind: "warning", text: "Din tur — 15 sekunder tilbage" })
  })

  test("a refused move is a notice, hjerterfri's and es-makker's reasons alike", () => {
    assert.deepEqual(route({ type: "rejected", reason: "not_your_turn" }), { kind: "rejected", notice: "Det er ikke din tur." })
    assert.equal(route({ type: "rejected", reason: "bank_window_closed" }).kind, "rejected")
  })
})

describe("a refused subscription", () => {
  test("goes on to the new bord after the spil, or says you do not sit here", () => {
    assert.deepEqual(routeRefusal("/borde/next"), { kind: "go", to: "/borde/next" })
    assert.deepEqual(routeRefusal(null), { kind: "refused" })
  })
})

describe("the leave confirmation", () => {
  test("says a bot takes your seat, except at an øvebord", () => {
    assert.match(leaveConfirmText(false), /en bot overtager din plads/)
    assert.equal(leaveConfirmText(true), "Forlad bordet? Spillet slutter her.")
    assert.equal(leaveConfirmText(false, false), "Forlad bordet? Du taber spillet, og det slutter for alle ved bordet.")
  })
})
