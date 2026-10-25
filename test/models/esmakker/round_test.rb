require "test_helper"

module Esmakker
  # Seam 1: what a seat of a dealt runde sees, who deals, and the runde
  # rebuilt from its stored form.
  class RoundTest < ActiveSupport::TestCase
    setup do
      @deal = Deal.shuffled(shuffler: Random.new(3))
      @round = Round.new(rules: Rules.standard, deal: @deal, dealer: 2)
    end

    test "a seat sees its own 13 cards and only how many the others and the kitty hold" do
      view = @round.view_for(1)

      assert_equal @deal.hand(1).map(&:to_s).sort, view[:hand].sort
      assert_equal({ 0 => 13, 2 => 13, 3 => 13 }, view[:card_counts])
      assert_equal 3, view[:kitty_count]
      hidden = (@deal.hands.values_at(0, 2, 3).flatten + @deal.kitty).map(&:to_s)
      assert_empty hidden & view.to_json.scan(/"([2-9TJQKA][CDHS]|X\d)"/).flatten, "no other seat's card and no kitty card"
    end

    test "the hand is shown by suit, colours alternating, ace high, jokers last" do
      hand = %w[X2 AH 2C KS TD X1 3C 9H JD QS 4S 5D 7H]
      deal = Deal.parse((hand + (Card.deck.map(&:to_s) - hand)).join(" "))

      shown = Round.new(rules: Rules.standard, deal:, dealer: 0).view_for(0)[:hand]

      assert_equal %w[2C 3C 5D TD JD 4S QS KS 7H 9H AH X1 X2], shown
    end

    test "the forhånd is the seat after the kortgiver, and the kortgiver moves clockwise" do
      assert_equal 2, @round.view_for(0)[:dealer]
      assert_equal 3, @round.view_for(0)[:forhand]
      assert_equal 3, @round.next_dealer

      last = Round.new(rules: Rules.standard, deal: @deal, dealer: 3)
      assert_equal 0, last.forhand
      assert_equal 0, last.next_dealer
      assert_equal [ 1, 2, 3, 0 ], (0..3).map { |dealer| Seats.forhand(dealer) }
    end

    test "the runde waits for the meldingsrunde: nobody is to act, and no intent is taken yet" do
      view = @round.view_for(0)

      assert_equal :bidding, view[:phase]
      assert_nil view[:to_act]
      assert_empty @round.seats_to_act
      assert_equal :unknown_intent, @round.apply(3, Object.new).reason
      assert_not @round.complete?
    end

    test "a runde is stored as its deal and its action log, and replays to the same state" do
      rebuilt = Round.from_strings(rules: Rules.standard, deal: @round.deal_string, dealer: 2, actions: @round.actions_string)

      assert_equal 55, @round.deal_string.split.size
      assert_equal "", @round.actions_string
      assert_equal @round, rebuilt
      (0..3).each { |seat| assert_equal @round.view_for(seat), rebuilt.view_for(seat) }
    end

    test "a seeded deal replays the same from storage every time" do
      stored = Deal.shuffled(shuffler: Random.new(11)).to_s

      first = Round.from_strings(rules: Rules.standard, deal: stored, dealer: 1)
      second = Round.from_strings(rules: Rules.standard, deal: Deal.shuffled(shuffler: Random.new(11)).to_s, dealer: 1)

      assert_equal first, second
    end

    test "a corrupt stored runde does not load" do
      assert_raises(ArgumentError) { Round.from_strings(rules: Rules.standard, deal: @round.deal_string, dealer: 4) }
      assert_raises(ArgumentError) { Round.from_strings(rules: Rules.standard, deal: @round.deal_string, dealer: 0, actions: "nonsense") }
      assert_raises(ArgumentError) { Round.from_strings(rules: Rules.standard, deal: @round.deal_string, dealer: 0, actions: "1:pas") }
    end

    test "the action log is seat:token entries" do
      actions = Action.parse_log("1:pas 2:9")

      assert_equal [ Action.new(seat: 1, token: "pas"), Action.new(seat: 2, token: "9") ], actions
      assert_equal "1:pas 2:9", Action.log_string(actions)
      assert_raises(ArgumentError) { Action.parse("5:pas") }
    end
  end
end
