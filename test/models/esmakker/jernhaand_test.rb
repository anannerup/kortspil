require "test_helper"

module Esmakker
  class JernhaandTest < ActiveSupport::TestCase
    NUMBERS_ONLY = %w[2C 3C 4C 5D 6D 7D 8H 9H TH 2S 3S 4S 5S].freeze

    test "13 number cards is a jernhånd" do
      assert Jernhaand.hand?(NUMBERS_ONLY)
      assert Jernhaand.hand?(NUMBERS_ONLY.map { |code| code.sub("T", "10") })
    end

    test "a picture card, an ace or a joker spoils it" do
      %w[JS QS KS AS JK X1].each do |card|
        assert_not Jernhaand.hand?([ *NUMBERS_ONLY.first(12), card ]), card
      end
    end

    test "it takes 13 cards" do
      assert_not Jernhaand.hand?(NUMBERS_ONLY.first(12))
    end
  end
end
