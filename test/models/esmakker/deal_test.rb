require "test_helper"

module Esmakker
  class DealTest < ActiveSupport::TestCase
    test "the deck holds 55 unique cards: the 52 playing cards and three jokers" do
      codes = Card.deck.map(&:to_s)

      assert_equal 55, codes.size
      assert_equal 55, codes.uniq.size
      assert_equal %w[X1 X2 X3], Card.deck.select(&:joker?).map(&:to_s)
      assert_equal Hjerterfri::Card.deck.map(&:to_s).sort, (codes - %w[X1 X2 X3]).sort
    end

    test "a joker's code never reads as a playing card, and every code round-trips" do
      Card.deck.each { |card| assert_equal card, Card.parse(card.to_s) }
      %w[X1 X2 X3].each { |code| assert_not Hjerterfri::Card.valid?(code) }
      %w[X0 X4 XC JX 1C].each { |code| assert_not Card.valid?(code), code }
    end

    test "deals 13 cards to each seat and 3 to the kitty, covering the whole deck" do
      deal = Deal.shuffled(shuffler: Random.new(1))

      assert_equal [ 13 ] * 4, deal.hands.map(&:size)
      assert_equal 3, deal.kitty.size
      assert_equal Card.deck.map(&:to_s).sort, (deal.hands.flatten + deal.kitty).map(&:to_s).sort
    end

    test "the same seed gives the same deal" do
      assert_equal Deal.shuffled(shuffler: Random.new(7)), Deal.shuffled(shuffler: Random.new(7))
      assert_not_equal Deal.shuffled(shuffler: Random.new(7)), Deal.shuffled(shuffler: Random.new(8))
    end

    test "round-trips through its stored string: the hands in seat order, then the kitty" do
      deal = Deal.shuffled(shuffler: Random.new(2))
      codes = deal.to_s.split

      assert_equal 55, codes.size
      assert_equal deal.hand(1).map(&:to_s), codes[13, 13]
      assert_equal deal.kitty.map(&:to_s), codes.last(3)
      assert_equal deal, Deal.parse(deal.to_s)
    end

    test "refuses a string that is not a full deal" do
      codes = Card.deck.map(&:to_s)

      assert_raises(ArgumentError) { Deal.parse(codes.first(54).join(" ")) }
      assert_raises(ArgumentError) { Deal.parse((codes.first(54) + [ "2C" ]).join(" ")) }
      assert_raises(ArgumentError) { Deal.parse((codes.first(54) + [ "X9" ]).join(" ")) }
      assert_raises(ArgumentError) { Deal.parse(Hjerterfri::Deal.shuffled(shuffler: Random.new(1)).to_s) }
    end
  end
end
