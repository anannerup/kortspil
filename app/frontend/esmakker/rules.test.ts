import assert from "node:assert/strict"
import { describe, test } from "node:test"
import type { EsmakkerRules } from "./messages"
import { afkastLine, amount, esmakkerSettingsFields, esmakkerSummary, movePahaeng, pahaengLine } from "./rules.ts"

const rules: EsmakkerRules = {
  pahaeng_order: ["vip", "halve", "gode"],
  joker_trumpable: false,
  esmakker_banks_first: true,
  bank_window: 8,
  afkast: "renonce",
  points: { stakes: { "8": 1, "9": 1.5, "10": 2, "11": 2.5, "12": 3, "13": 3.5 }, pahaeng: 2, trumflos: 2, klor: 2, vip_first: 2, vip_second: 4, vip_third: 8, bank: 2, sol: 3, ren_sol: 4, bordlaegger: 5, ren_bordlaegger: 6 },
}

describe("es-makker's rules in words", () => {
  test("the påhæng order, amounts and the lobby's summary", () => {
    assert.equal(pahaengLine(rules.pahaeng_order), "Vip > Halve > Gode")
    assert.equal(amount(1.5), "1,5")
    assert.equal(afkastLine("renonce"), "Afkast (bots): Renonce — afkast i en farve betyder: jeg prøver at blive renonce i den")
    assert.equal(afkastLine("spil_den_her"), "Afkast (bots): Spil den her — afkast i en farve betyder: spil den her til mig")
    assert.equal(esmakkerSummary(rules, 10), "10 runder · Vip > Halve > Gode · Jokere kan ikke stikkes")
  })

  test("a påhæng moves one tier at a time and never off the ends", () => {
    assert.deepEqual(movePahaeng(rules.pahaeng_order, 2, -1), ["vip", "gode", "halve"])
    assert.deepEqual(movePahaeng(rules.pahaeng_order, 0, -1), ["vip", "halve", "gode"])
    assert.deepEqual(movePahaeng(rules.pahaeng_order, 2, 1), ["vip", "halve", "gode"])
  })
})

describe("the settings form", () => {
  test("holds the type, the runder and every rule, as the server reads them", () => {
    const fields = esmakkerSettingsFields(rules, 15, "password", "hemmelig")
    assert.equal(fields.kind, "password")
    assert.equal(fields.password, "hemmelig")
    assert.equal(fields.runder, "15")
    assert.equal(fields["rules[pahaeng_order]"], "vip,halve,gode")
    assert.equal(fields["rules[joker_trumpable]"], "0")
    assert.equal(fields["rules[esmakker_banks_first]"], "1")
    assert.equal(fields["rules[bank_window]"], "8")
    assert.equal(fields["rules[afkast]"], "renonce")
    assert.equal(esmakkerSettingsFields({ ...rules, afkast: "spil_den_her" }, 10, "open")["rules[afkast]"], "spil_den_her")
    assert.equal(fields["rules[points][stakes][9]"], "1.5")
    assert.equal(fields["rules[points][ren_bordlaegger]"], "6")
  })
})
