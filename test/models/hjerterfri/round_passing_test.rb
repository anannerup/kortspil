require "test_helper"

module Hjerterfri
  # The pass before play (docs/rules §3.3). Seats are 0–3 clockwise; left is
  # the next seat clockwise.
  class RoundPassingTest < ActiveSupport::TestCase
    # Each seat holds one whole suit: 0 clubs, 1 diamonds, 2 spades, 3 hearts.
    BY_SUIT = %w[C D S H].map { |suit| Card::RANKS.map { |rank| "#{rank}#{suit}" } }
    # Each seat passes its three lowest cards.
    LOWEST = BY_SUIT.map { |hand| hand.first(3) }

    test "the direction cycles left, right, across, none by runde number and wraps at runde 5" do
      assert_equal %i[left right across none left right across none left], (1..9).map { |number| PassDirection.for_runde(number) }
      assert_raises(ArgumentError) { PassDirection.for_runde(0) }
    end

    test "left is the next seat clockwise, right the previous, across the one opposite" do
      assert_equal [ 1, 3, 2, 0 ], %i[left right across none].map { |direction| PassDirection.receiver(0, direction) }
      assert_equal [ 0, 2, 1, 3 ], %i[left right across none].map { |direction| PassDirection.receiver(3, direction) }
    end

    test "each direction moves every seat's pass to the right receiver" do
      { left: 1, right: 3, across: 2 }.each do |direction, offset|
        round = pass_all(round_for(direction), LOWEST)

        (0..3).each do |seat|
          giver = (seat - offset) % 4
          assert_equal LOWEST[giver], round.view_for(seat)[:received_cards], "#{direction}, seat #{seat}"
          assert_equal (BY_SUIT[seat].drop(3) + LOWEST[giver]).sort_by { |code| Card.parse(code).display_key },
            round.view_for(seat)[:hand]
        end
      end
    end

    test "a runde without passing starts in play and refuses a pass" do
      round = round_for(:none)

      assert_equal :playing, round.phase
      assert_equal 0, round.to_act
      assert_rejected :not_passing, round.apply(0, Pass.new(cards: LOWEST[0]))
      assert_equal :none, round.view_for(0)[:pass_direction]
      assert_equal [], round.view_for(0)[:received_cards]
    end

    test "a runde with passing starts in the passing phase, where nobody may play" do
      round = round_for(:left)

      assert_equal :passing, round.phase
      assert_nil round.to_act
      (0..3).each { |seat| assert_equal [], round.legal_moves(seat) }
      assert_rejected :passing_not_complete, round.apply(0, Play.new(card: "2C"))
    end

    test "a pass must be exactly three cards" do
      round = round_for(:left)

      assert_rejected :wrong_card_count, round.apply(0, Pass.new(cards: %w[2C 3C]))
      assert_rejected :wrong_card_count, round.apply(0, Pass.new(cards: %w[2C 3C 4C 5C]))
      assert_rejected :wrong_card_count, round.apply(0, Pass.new(cards: []))
      assert_rejected :wrong_card_count, round.apply(0, Pass.new(cards: "2C 3C 4C"))
    end

    test "a pass must be three different cards" do
      assert_rejected :duplicate_cards, round_for(:left).apply(0, Pass.new(cards: %w[2C 2C 3C]))
    end

    test "a pass must come from the seat's own hand" do
      round = round_for(:left)

      assert_rejected :card_not_in_hand, round.apply(0, Pass.new(cards: %w[2C 3C 2D]))
      assert_rejected :card_not_in_hand, round.apply(0, Pass.new(cards: %w[2C 3C ZZ]))
    end

    test "a seat passes once" do
      round = pass_cards(round_for(:left), 0, LOWEST[0])

      assert_rejected :already_passed, round.apply(0, Pass.new(cards: BY_SUIT[0].last(3)))
    end

    test "a seat that does not exist cannot pass" do
      assert_rejected :not_your_turn, round_for(:left).apply(4, Pass.new(cards: LOWEST[0]))
    end

    test "no pass once passing is complete or the runde is over" do
      round = pass_all(round_for(:left), LOWEST)

      assert_rejected :not_passing, round.apply(0, Pass.new(cards: round.view_for(0)[:hand].first(3)))
      round = play_out(round)
      assert_rejected :round_complete, round.apply(0, Pass.new(cards: %w[2C 3C 4C]))
    end

    test "passes are hidden until all four seats have passed" do
      round = [ 2, 0, 3 ].reduce(round_for(:across)) { |current, seat| pass_cards(current, seat, LOWEST[seat]) }

      assert_equal :passing, round.phase
      (0..3).each do |seat|
        view = round.view_for(seat)
        assert_equal BY_SUIT[seat], view[:hand], "hands do not change until everyone has passed"
        assert_equal [], view[:received_cards]
        assert_equal [ 0, 2, 3 ], view[:passed_seats]
        assert_equal({ 0 => 13, 1 => 13, 2 => 13, 3 => 13 }.except(seat), view[:card_counts])
        shown = view.except(:hand, :own_pass).to_s.scan(/\b[2-9TJQKA][CDHS]\b/)
        assert_empty shown, "seat #{seat} sees cards it does not hold"
      end
      assert_equal LOWEST[2], round.view_for(2)[:own_pass]
      assert_equal [], round.view_for(1)[:own_pass]
    end

    test "after the pass the round is in play and the holder of 2♣ leads" do
      round = pass_all(round_for(:left), LOWEST)

      assert_equal :playing, round.phase
      assert_equal 1, round.to_act
      assert_equal [ "2C" ], round.legal_moves(1)
      assert_rejected :not_your_turn, round.apply(0, Play.new(card: "5C"))
      assert_accepted round.apply(1, Play.new(card: "2C"))
    end

    test "the 2♣ holder after the pass leads even when 2♣ was not passed" do
      round = pass_all(round_for(:right), BY_SUIT.map { |hand| hand.last(3) })

      assert_equal 0, round.to_act
    end

    test "a received card stays marked as received in the view" do
      round = play(pass_all(round_for(:left), LOWEST), "2C")

      assert_equal %w[2C 3C 4C], round.view_for(1)[:received_cards]
      assert_equal %w[2D 3D 4D], round.view_for(1)[:own_pass]
    end

    test "passes are stored as 12 codes in seat order, with -- for seats that have not passed" do
      round = pass_cards(pass_cards(round_for(:left), 2, LOWEST[2]), 0, %w[4C 2C 3C])

      assert_equal "4C 2C 3C -- -- -- 2S 3S 4S -- -- --", round.passes_string
      assert_equal "", round_for(:left).passes_string
      assert_equal LOWEST.flatten.join(" "), pass_all(round_for(:left), LOWEST).passes_string
    end

    test "rebuilding from the stored strings reproduces passes and post-pass hands" do
      round = round_for(:across)
      [ 3, 1, 0, 2 ].each do |seat|
        round = pass_cards(round, seat, LOWEST[seat])
        assert_equal round, rebuild(round)
      end
      round = 3.times.reduce(round) { |current, _| play(current, current.legal_moves(current.to_act).first) }
      rebuilt = rebuild(round)

      assert_equal round, rebuilt
      (0..3).each { |seat| assert_equal round.view_for(seat), rebuilt.view_for(seat) }
    end

    test "stored passes that break the rules are refused" do
      deal = BY_SUIT.flatten.join(" ")
      corrupt = [
        { pass_direction: "none", passes: LOWEST.flatten.join(" "), plays: "" },
        { pass_direction: "left", passes: "2C 3C 2D -- -- -- -- -- -- -- -- --", plays: "" },
        { pass_direction: "left", passes: "2C 2C 3C -- -- -- -- -- -- -- -- --", plays: "" },
        { pass_direction: "left", passes: "2C 3C -- -- -- -- -- -- -- -- -- --", plays: "" },
        { pass_direction: "left", passes: "2C 3C 4C", plays: "" },
        { pass_direction: "left", passes: "", plays: "2C" },
        { pass_direction: "sideways", passes: "", plays: "" }
      ]

      corrupt.each do |stored|
        assert_raises(ArgumentError, stored.inspect) { Round.from_strings(rules: Rules.standard, deal:, **stored) }
      end
    end

    private

    def round_for(direction, hands: BY_SUIT)
      Round.from_strings(rules: Rules.standard, deal: hands.flatten.join(" "), passes: "", plays: "", pass_direction: direction.to_s)
    end

    def rebuild(round)
      Round.from_strings(rules: round.rules, deal: round.deal_string, passes: round.passes_string, plays: round.plays_string,
        pass_direction: round.pass_direction.to_s)
    end

    def pass_cards(round, seat, cards)
      result = round.apply(seat, Pass.new(cards:))
      assert result.accepted?, "pass by seat #{seat} was rejected: #{result.reason}"
      result.round
    end

    def pass_all(round, passes) = passes.each_with_index.reduce(round) { |current, (cards, seat)| pass_cards(current, seat, cards) }

    def play(round, *codes)
      codes.reduce(round) do |current, code|
        result = current.apply(current.to_act, Play.new(card: code))
        assert result.accepted?, "#{code} was rejected: #{result.reason}"
        result.round
      end
    end

    def play_out(round)
      round = play(round, round.legal_moves(round.to_act).first) until round.complete?
      round
    end

    def assert_rejected(reason, result)
      assert result.rejected?
      assert_equal reason, result.reason
      assert_nil result.round
    end

    def assert_accepted(result)
      assert result.accepted?, "rejected: #{result.reason}"
      assert_kind_of Round, result.round
    end
  end
end
