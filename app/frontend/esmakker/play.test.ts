import assert from "node:assert/strict"
import { describe, test } from "node:test"
import type { EsmakkerView, PlayView, RundeResultView } from "./messages"
import {
  aceChoiceTitle,
  aceLabel,
  acceptTrumpLabel,
  cardLabel,
  contractText,
  declarationText,
  overviewRows,
  playTurnText,
  resultText,
  roleOf,
  trumpChoiceTitle,
  trumpLabel,
  trumpOfCard,
  turnCardLabel,
} from "./play.ts"

const names = { me: 0, names: ["Anders", "Bent", "Carla", "Dennis"] }

const play = (over: Partial<PlayView> = {}): PlayView => ({
  trump: "H",
  called_ace: "D",
  esmakker: null,
  selvmakker: false,
  turned: [],
  vip_card: null,
  kitty_cards: [],
  discarded: [],
  current_trick: [],
  last_trick: [],
  last_trick_winner: null,
  tricks_won: [0, 0, 0, 0],
  side_stik: null,
  legal_moves: [],
  ...over,
})

const view = (over: Partial<EsmakkerView> = {}): EsmakkerView => ({
  seat: 0,
  phase: "playing",
  hand: ["2C", "3C", "4D"],
  card_counts: { "1": 3, "2": 3, "3": 3 },
  kitty_count: 0,
  dealer: 0,
  forhand: 1,
  to_act: 0,
  bidding: {
    phase: "complete",
    forhand: 1,
    dealer: 0,
    to_act: null,
    melding: "9",
    holder: 1,
    serveret: null,
    passed: [2, 3, 0],
    went_with: [],
    history: [],
    outcome: { kind: "melder", melder: 1, melding: "9", went_with: [], reason: null, dealer: null },
  },
  choices: { meldinger: [], det_kan_jeg_selv: false, gaa_med: false, pas: false, jernhaand: false, trumps: [], aces: [], turn_card: false, accept_trump: false, discard: false },
  play: play(),
  result: null,
  ...over,
})

const result = (over: Partial<RundeResultView> = {}): RundeResultView => ({
  kind: "played",
  melder: 1,
  melding: "9",
  trump: "H",
  called_ace: "D",
  esmakker: 2,
  selvmakker: false,
  tricks_won: [2, 5, 5, 1],
  stik: 10,
  gik_hjem: true,
  vip_card: null,
  banks: 0,
  points: [-3, 3, 3, -3],
  ...over,
})

describe("trump and the called ace", () => {
  test("in words", () => {
    assert.equal(trumpLabel("S"), "spar")
    assert.equal(trumpLabel("trumfloes"), "trumfløs")
    assert.equal(aceLabel("D"), "ruder-es")
  })

  test("the contract shows the melding, then trump and the ace once named", () => {
    assert.equal(contractText(view()), "9 · trumf: hjerter · ruder-es")
    assert.equal(contractText(view({ play: play({ trump: "trumfloes", called_ace: null }) })), "9 · trumfløs")
    assert.equal(contractText(view({ play: null })), null)
  })
})

describe("the melder declares", () => {
  test("the melder is told what to do, the others what she does", () => {
    const choosing = view({ phase: "choosing_trump", play: play({ trump: null, called_ace: null }) })
    assert.deepEqual(declarationText(choosing, names), { headline: "Melder: Bent — 9", detail: "Bent vælger trumf …" })
    assert.deepEqual(declarationText(choosing, { ...names, me: 1 }), { headline: "Du er melder — 9", detail: "Vælg trumf: en farve eller trumfløs." })
    assert.equal(declarationText(view({ phase: "discarding" }), names)?.detail, "Bent tager katten og lægger 3 kort væk …")
    assert.equal(declarationText(view(), names), null)
  })
})

describe("halve", () => {
  const halve = (over: Partial<EsmakkerView> = {}) =>
    view({
      bidding: { ...view().bidding, melding: "9halve", outcome: { kind: "melder", melder: 1, melding: "9halve", went_with: [], reason: null, dealer: null } },
      ...over,
    })

  test("the melder calls the ace: »jeg er makker til …«", () => {
    const calling = halve({ phase: "calling_ace", to_act: 1, play: play({ trump: null, called_ace: null }) })
    assert.equal(declarationText(calling, { ...names, me: 1 })?.detail, "Sig »jeg er makker til …«: kald et es, du ikke selv har.")
    assert.equal(declarationText(calling, names)?.detail, "Bent kalder et es: »jeg er makker til …«")
    assert.equal(aceChoiceTitle("9halve"), "Jeg er makker til …")
    assert.equal(aceChoiceTitle("9"), "Kald et es")
  })

  test("the ace's holder is makker to everyone, and names trump, not the ace's suit", () => {
    const choosing = halve({ phase: "choosing_trump", to_act: 0, play: play({ trump: null, esmakker: 0 }) })
    assert.equal(declarationText(choosing, names)?.detail, "Du har ruder-es og er makker. Vælg trumf (ikke ruder) eller trumfløs.")
    assert.equal(declarationText(choosing, { ...names, me: 1 })?.detail, "Anders er din makker (har ruder-es) og vælger trumf …")
    assert.equal(declarationText(choosing, { ...names, me: 3 })?.detail, "Anders er makker (har ruder-es) og vælger trumf …")
    assert.equal(roleOf(0, choosing), "makker")
    assert.equal(trumpChoiceTitle(choosing), "Vælg trumf (ikke ruder)")
    assert.equal(trumpChoiceTitle(view({ phase: "choosing_trump" })), "Vælg trumf")
  })

  test("the makker lays the kitty away", () => {
    const discarding = halve({ phase: "discarding", to_act: 2, play: play({ esmakker: 2 }) })
    assert.equal(declarationText(discarding, names)?.detail, "Carla tager katten og lægger 3 kort væk …")
    assert.equal(declarationText(discarding, { ...names, me: 2 })?.detail, "Du har taget katten. Læg 3 kort væk.")
  })

  test("the ace in the kitty: the melder is selvmakker and names trump herself", () => {
    const alone = halve({ phase: "choosing_trump", to_act: 1, play: play({ trump: null, selvmakker: true }) })
    assert.equal(declarationText(alone, { ...names, me: 1 })?.detail, "Ruder-es ligger i katten: du er selvmakker. Vælg trumf (ikke ruder) eller trumfløs.")
    assert.equal(declarationText(alone, names)?.detail, "Ruder-es ligger i katten: Bent er selvmakker og vælger trumf …")
    assert.equal(roleOf(1, alone), "melder · alene")
  })
})

describe("vip", () => {
  const vip = (over: Partial<EsmakkerView> = {}) =>
    view({
      bidding: { ...view().bidding, melding: "9vip", outcome: { kind: "melder", melder: 1, melding: "9vip", went_with: [], reason: null, dealer: null } },
      ...over,
    })
  const melder = { ...names, me: 1 }

  test("the melder calls the ace first, then turns the kitty", () => {
    const calling = vip({ phase: "calling_ace", to_act: 1, play: play({ trump: null, called_ace: null }) })
    assert.equal(declarationText(calling, melder)?.detail, "Kald et es, du ikke selv har. Så vender du katten for at finde trumf.")
    assert.equal(declarationText(calling, names)?.detail, "Bent kalder et es og vender så katten …")
    assert.equal(aceChoiceTitle("9vip"), "Kald et es")
  })

  test("each card turned is named, and the melder asked whether it is trump", () => {
    const none = vip({ phase: "turning", to_act: 1, play: play({ trump: null }) })
    assert.equal(declarationText(none, melder)?.detail, "Vend kattens første kort.")
    assert.equal(declarationText(none, names)?.detail, "Bent vender kattens første kort …")
    const one = vip({ phase: "turning", to_act: 1, play: play({ trump: null, turned: ["QS"] }) })
    assert.equal(declarationText(one, melder)?.detail, "1. kort: spar dame. Er det trumf, eller vender du det næste?")
    assert.equal(declarationText(one, names)?.detail, "Bent har vendt spar dame (1. kort) …")
    const two = vip({ phase: "turning", to_act: 1, play: play({ trump: null, turned: ["QS", "X2"] }) })
    assert.equal(declarationText(two, melder)?.detail, "2. kort: joker. Er det trumf, eller vender du det sidste (trumf uanset)?")
  })

  test("the buttons: the next card (the third is trump in any case) and the card turned last as trump", () => {
    assert.deepEqual([0, 1, 2].map(turnCardLabel), ["Vend 1. kort", "Vend 2. kort", "Vend 3. kort (trumf uanset)"])
    assert.equal(acceptTrumpLabel(["5D"]), "Det er trumf: ruder")
    assert.equal(acceptTrumpLabel(["5D", "X1"]), "Det er trumf: trumfløs")
    assert.deepEqual([trumpOfCard("TH"), trumpOfCard("X3")], ["H", "trumfloes"])
    assert.deepEqual(["TH", "AC", "7D", "X1"].map(cardLabel), ["hjerter 10", "klør es", "ruder 7", "joker"])
  })

  test("once a card is taken, trump and which card show while the kitty is laid away, in the contract and the overview", () => {
    const discarding = vip({ phase: "discarding", to_act: 1, play: play({ trump: "S", turned: ["5D", "QS"], vip_card: 2 }) })
    assert.equal(declarationText(discarding, melder)?.detail, "Trumf: spar (2. kort). Du har taget katten. Læg 3 kort væk.")
    assert.equal(declarationText(discarding, names)?.detail, "Trumf: spar (2. kort). Bent tager katten og lægger 3 kort væk …")
    const joker = vip({ phase: "discarding", to_act: 1, play: play({ trump: "trumfloes", turned: ["X1"], vip_card: 1 }) })
    assert.equal(declarationText(joker, names)?.detail, "Trumfløs (1. kort). Bent tager katten og lægger 3 kort væk …")
    assert.equal(contractText(discarding), "9 vip · trumf: spar · 2. kort · ruder-es")
    assert.equal(overviewRows([result({ melding: "9vip", trump: "S", vip_card: 2 })], names.names)[0]?.trump, "spar (2. kort)")
  })
})

describe("the play", () => {
  test("roles appear only once known", () => {
    assert.equal(roleOf(1, view()), "melder")
    assert.equal(roleOf(2, view()), null)
    assert.equal(roleOf(2, view({ play: play({ esmakker: 2 }) })), "makker")
    assert.equal(roleOf(1, view({ play: play({ selvmakker: true }) })), "melder · alene")
  })

  test("whose turn, and a hint to follow suit when not every card may be played", () => {
    assert.equal(playTurnText(view({ to_act: 2 }), names), "Venter på Carla …")
    assert.equal(playTurnText(view(), names), "Din tur: spil ud.")
    const following = view({ play: play({ current_trick: [{ seat: 3, card: "5C" }], legal_moves: ["2C", "3C"] }) })
    assert.equal(playTurnText(following, names), "Din tur: bekend kulør.")
    assert.equal(playTurnText(view({ phase: "complete" }), names), null)
  })
})

describe("the runde result", () => {
  test("gik hjem with overstik, bet with the missing stik, selvmakker alone", () => {
    assert.deepEqual(resultText(result(), names), { headline: "9 gik hjem", detail: "Bent og Carla tog 10 stik (1 overstik)." })
    assert.deepEqual(resultText(result({ stik: 7, gik_hjem: false, esmakker: 0 }), names), { headline: "9 gik bet", detail: "Bent og dig tog 7 stik — 2 for lidt." })
    assert.equal(resultText(result({ esmakker: null, selvmakker: true, stik: 9 }), names).detail, "Bent alene tog 9 stik.")
  })

  test("a melding not played yet says so", () => {
    const text = resultText(result({ kind: "not_played", melding: "10vip", trump: null, called_ace: null, esmakker: null, stik: 0, gik_hjem: false }), names)
    assert.equal(text.headline, "10 vip spilles ikke endnu")
  })

  test("the overview has one row per completed runde", () => {
    const rows = overviewRows([result(), result({ kind: "not_played", melding: "8vip", trump: null, called_ace: null, esmakker: null, stik: 0, gik_hjem: false }), result({ selvmakker: true, esmakker: null, gik_hjem: false, stik: 6 })], names.names)
    assert.deepEqual(rows[0], { number: 1, melder: "Bent", melding: "9", trump: "hjerter", ace: "ruder-es", makker: "Carla", stik: "10", outcome: "Hjem" })
    assert.deepEqual([rows[1]?.makker, rows[1]?.outcome], ["–", "Ikke spillet"])
    assert.deepEqual([rows[2]?.makker, rows[2]?.outcome], ["alene", "Bet"])
  })
})
