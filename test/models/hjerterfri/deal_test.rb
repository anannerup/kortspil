require "test_helper"

module Hjerterfri
  class DealTest < ActiveSupport::TestCase
    test "the same seed gives the same deal" do
      assert_equal Deal.shuffled(shuffler: Random.new(7)), Deal.shuffled(shuffler: Random.new(7))
      refute_equal Deal.shuffled(shuffler: Random.new(7)), Deal.shuffled(shuffler: Random.new(8))
    end

    test "deals four hands of 13 covering the whole deck" do
      deal = Deal.shuffled(shuffler: Random.new(1))

      assert_equal [ 13 ] * 4, deal.hands.map(&:size)
      assert_equal Card.deck.sort_by(&:to_s), deal.hands.flatten.sort_by(&:to_s)
    end

    test "round-trips through its stored string, 13 codes per seat in seat order" do
      deal = Deal.shuffled(shuffler: Random.new(2))
      codes = deal.to_s.split

      assert_equal 52, codes.size
      assert_equal deal.hand(1).map(&:to_s), codes[13, 13]
      assert_equal deal, Deal.parse(deal.to_s)
    end

    test "refuses a string that is not a full deal" do
      codes = Card.deck.map(&:to_s)

      assert_raises(ArgumentError) { Deal.parse(codes.first(51).join(" ")) }
      assert_raises(ArgumentError) { Deal.parse((codes.first(51) + [ "2C" ]).join(" ")) }
      assert_raises(ArgumentError) { Deal.parse((codes.first(51) + [ "XX" ]).join(" ")) }
    end
  end
end
