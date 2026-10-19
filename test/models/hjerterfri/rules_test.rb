require "test_helper"

module Hjerterfri
  class RulesTest < ActiveSupport::TestCase
    test "the standard preset ends at 100 with both house rules off" do
      assert_equal({ end_score: 100, queen_breaks_hearts: false, jack_of_diamonds_minus_ten: false }, Rules.standard.to_h)
    end

    test "round-trips through a plain hash and JSON" do
      rules = Rules.new(end_score: 50, queen_breaks_hearts: true, jack_of_diamonds_minus_ten: true)

      assert_equal rules, Rules.from_h(rules.to_h)
      assert_equal rules, Rules.from_h(JSON.parse(rules.to_h.to_json))
    end

    test "missing keys take the standard value" do
      assert_equal Rules.standard, Rules.from_h({})
      assert_equal Rules.new(end_score: 75), Rules.from_h("end_score" => 75)
    end

    test "refuses unknown keys and invalid values" do
      [
        { "ten_of_diamonds" => true },
        { end_score: 0 },
        { end_score: "100" },
        { queen_breaks_hearts: "yes" },
        { jack_of_diamonds_minus_ten: nil }
      ].each { |hash| assert_raises(ArgumentError, hash.inspect) { Rules.from_h(hash) } }
    end
  end
end
