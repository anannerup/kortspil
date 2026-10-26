require "test_helper"

module Esmakker
  class RulesTest < ActiveSupport::TestCase
    test "the standard rules are REGLER §2.0's" do
      rules = Rules.standard

      assert_equal %w[vip halve gode], rules.pahaeng_order
      assert_equal false, rules.joker_trumpable
      assert_equal true, rules.esmakker_banks_first
      assert_equal 8, rules.bank_window
      assert_equal({ "8" => 1, "9" => 1.5, "10" => 2, "11" => 2.5, "12" => 3, "13" => 3.5 }, rules.points.stakes)
      assert_equal [ 2, 2, 2, 2, 4, 8, 2 ], rules.points.to_h.values_at(:pahaeng, :trumflos, :klor, :vip_first, :vip_second, :vip_third, :bank)
      assert_equal [ 3, 4, 5, 6 ], rules.points.to_h.values_at(:sol, :ren_sol, :bordlaegger, :ren_bordlaegger)
    end

    test "round-trips through a plain hash and JSON" do
      rules = Rules.new(pahaeng_order: %w[halve vip gode], joker_trumpable: true, esmakker_banks_first: false, bank_window: 5,
                        points: Points.from_h(stakes: { "8" => 2 }, sol: 3.5))

      assert_equal rules, Rules.from_h(rules.to_h)
      assert_equal rules, Rules.from_h(JSON.parse(rules.to_h.to_json))
      assert_equal rules, Rules.from_stored(JSON.parse(rules.to_h.to_json).merge("unknown" => 1))
    end

    test "missing keys take the standard value" do
      assert_equal Rules.standard, Rules.from_stored({})
      assert_equal 3, Rules.from_stored("points" => { "sol" => 3 }).points.sol
    end

    test "refuses invalid values" do
      [
        { pahaeng_order: %w[vip vip gode] },
        { pahaeng_order: %w[vip halve] },
        { joker_trumpable: "no" },
        { bank_window: 4 },
        { bank_window: 11 },
        { points: { sol: 0 } },
        { points: { stakes: { "8" => -1 } } },
        { points: { stakes: { "7" => 1 } } }
      ].each { |hash| assert_raises(ArgumentError, hash.inspect) { Rules.from_h(hash) } }
    end

    test "reads the settings form, and nothing it cannot read" do
      form = { pahaeng_order: %w[gode halve vip], joker_trumpable: "1", esmakker_banks_first: "0", bank_window: "10",
               points: { stakes: { "8" => "1,5" }, bank: "3" } }

      rules = Rules.from_form(form)

      assert_equal %w[gode halve vip], rules.pahaeng_order
      assert_equal [ true, false, 10 ], [ rules.joker_trumpable, rules.esmakker_banks_first, rules.bank_window ]
      assert_equal 1.5, rules.points.stakes["8"]
      assert_equal 3, rules.points.bank
      assert_nil Rules.from_form(form.merge(bank_window: "12"))
      assert_nil Rules.from_form(form.merge(points: { bank: "x" }))
      assert_nil Rules.from_form(form.merge(pahaeng_order: %w[vip]))
    end
  end
end
