require "test_helper"

module Hjerterfri
  class CardTest < ActiveSupport::TestCase
    test "parses a code and writes it back" do
      %w[2C TD QS AH].each { |code| assert_equal code, Card.parse(code).to_s }
    end

    test "rejects codes that are not cards" do
      %w[1C ZZ 10H QX].push("", "QSX", nil).each do |code|
        refute Card.valid?(code)
        assert_raises(ArgumentError) { Card.parse(code) }
      end
    end

    test "a deck has 52 different cards" do
      assert_equal 52, Card.deck.uniq.size
    end

    test "hearts score 1, the queen of spades 13, everything else 0" do
      assert_equal 1, Card.parse("2H").points
      assert_equal 13, Card.parse("QS").points
      assert_equal 0, Card.parse("KS").points
      assert_equal 26, Card.deck.sum(&:points)
    end
  end
end
