require "test_helper"

module Hjerterfri
  # Rule edge cases on hand-crafted deals. Seats are 0–3 clockwise.
  class RoundTest < ActiveSupport::TestCase
    # Each seat holds one whole suit: 0 clubs, 1 diamonds, 2 spades, 3 hearts.
    BY_SUIT = %w[C D S H].map { |suit| Card::RANKS.map { |rank| "#{rank}#{suit}" } }

    MIXED = [
      %w[2C 3C 4C 5C 6C 7C 2D 3D 4D 5D 6D 7D 8D],
      %w[8C 9C TC 2S 3S 4S 5S 6S 7S 8S 9S TS QS],
      %w[9D TD JD QD KD AD 2H 3H 4H 5H 6H 7H 8H],
      %w[JC QC KC AC JS KS AS 9H TH JH QH KH AH]
    ]

    # Seat 1 holds A♣ and twelve hearts, so it wins the first stik holding only hearts.
    ONLY_HEARTS_LEADER = [
      %w[2C 3C 4C 5C 2D 3D 4D 5D 6D 7D 8D 9D TD],
      %w[AC 2H 3H 4H 5H 6H 7H 8H 9H TH JH QH KH],
      %w[6C 7C 8C 9C JD QD KD AD AH 2S 3S 4S 5S],
      %w[TC JC QC KC 6S 7S 8S 9S TS JS QS KS AS]
    ]

    # Seat 1 is void in clubs and holds only Q♠ and hearts.
    QUEEN_AND_HEARTS = [
      %w[2C 2D 3D 4D 5D 6D 7D 8D 9D TD JD QD KD],
      %w[QS 2H 3H 4H 5H 6H 7H 8H 9H TH JH QH KH],
      %w[3C 4C 5C 6C 7C 8C 9C TC JC QC KC AC AD],
      %w[AH 2S 3S 4S 5S 6S 7S 8S 9S TS JS KS AS]
    ]

    SPOILED_MOON = [
      %w[2C 3C 4C 5C 6C 7C 8C 9C TC JC QC KC AS],
      BY_SUIT[1],
      %w[AC 2S 3S 4S 5S 6S 7S 8S 9S TS JS QS KS],
      BY_SUIT[3]
    ]

    test "the 2♣ holder acts first and must lead the 2♣" do
      round = round_for(MIXED)

      assert_equal 0, round.to_act
      assert_equal [ "2C" ], round.legal_moves(0)
      assert_rejected :must_lead_two_of_clubs, round.apply(0, Play.new(card: "3C"))
      assert_accepted round.apply(0, Play.new(card: "2C"))
    end

    test "the 2♣ holder leads even when it is not seat 0" do
      round = round_for(BY_SUIT.rotate(-2))

      assert_equal 2, round.to_act
      assert_rejected :not_your_turn, round.apply(0, Play.new(card: "2D"))
    end

    test "only the seat to act may play" do
      round = play(round_for(MIXED), "2C")

      assert_equal 1, round.to_act
      assert_rejected :not_your_turn, round.apply(0, Play.new(card: "3C"))
      assert_rejected :not_your_turn, round.apply(2, Play.new(card: "9D"))
      assert_rejected :not_your_turn, round.apply(7, Play.new(card: "8C"))
    end

    test "a card must be in the hand of the seat playing it" do
      round = round_for(MIXED)

      assert_rejected :card_not_in_hand, round.apply(0, Play.new(card: "AS"))
      assert_rejected :card_not_in_hand, round.apply(0, Play.new(card: "ZZ"))
    end

    test "an intent that is not a play is rejected" do
      assert_rejected :unknown_intent, round_for(MIXED).apply(0, { card: "2C" })
    end

    test "a seat must follow suit when it can" do
      round = play(round_for(MIXED), "2C")

      assert_equal %w[8C 9C TC], round.legal_moves(1)
      assert_rejected :must_follow_suit, round.apply(1, Play.new(card: "QS"))
      assert_rejected :must_follow_suit, round.apply(1, Play.new(card: "2S"))
    end

    test "a seat that cannot follow suit may play another suit" do
      round = play(round_for(MIXED), "2C", "8C")

      assert_accepted round.apply(2, Play.new(card: "AD"))
    end

    test "no hearts or Q♠ on the first stik while the seat holds anything else" do
      round = play(round_for(MIXED), "2C", "8C")

      assert_equal %w[9D TD JD QD KD AD], round.legal_moves(2)
      assert_rejected :no_points_on_first_trick, round.apply(2, Play.new(card: "2H"))
    end

    test "Q♠ may not be discarded on the first stik while other spades are held" do
      round = play(round_for(BY_SUIT), "2C", "2D")

      refute_includes round.legal_moves(2), "QS"
      assert_rejected :no_points_on_first_trick, round.apply(2, Play.new(card: "QS"))
    end

    test "a seat holding nothing but hearts may play one on the first stik" do
      round = play(round_for(BY_SUIT), "2C", "2D", "2S")

      assert_equal BY_SUIT[3], round.legal_moves(3)
      assert_accepted round.apply(3, Play.new(card: "AH"))
    end

    test "a seat void in clubs holding only Q♠ and hearts may play any of them on the first stik" do
      round = play(round_for(QUEEN_AND_HEARTS), "2C")

      assert_equal QUEEN_AND_HEARTS[1].sort_by { |code| Card.parse(code).display_key }, round.legal_moves(1)
      assert_accepted round.apply(1, Play.new(card: "QS"))
      assert_accepted round.apply(1, Play.new(card: "2H"))
    end

    test "the highest card of the led suit takes the stik, even against a higher off-suit card" do
      round = play(round_for(MIXED), "2C", "8C", "AD", "JC")

      assert_equal 3, round.view_for(0)[:last_trick_winner]
      assert_equal 3, round.to_act
    end

    test "the stik winner leads the next stik" do
      round = play(round_for(MIXED), "2C", "TC", "AD", "AC")

      assert_equal 3, round.to_act
      assert_equal [], round.view_for(3)[:current_trick]
    end

    test "hearts cannot be led until broken" do
      round = play(round_for(MIXED), "2C", "8C", "9D", "AC")

      refute round.hearts_broken?
      assert_equal %w[JC QC KC JS KS AS], round.legal_moves(3)
      assert_rejected :hearts_not_broken, round.apply(3, Play.new(card: "9H"))
    end

    test "a heart discarded on an off-suit stik breaks hearts for the next lead" do
      round = play(round_for(MIXED), "2C", "8C", "9D", "AC", "KC", "3C", "9C", "2H")

      assert round.hearts_broken?
      assert_equal 3, round.to_act
      assert_includes round.legal_moves(3), "9H"
      assert_accepted round.apply(3, Play.new(card: "9H"))
    end

    test "a seat holding only hearts may lead one before hearts are broken" do
      round = play(round_for(ONLY_HEARTS_LEADER), "2C", "AC", "6C", "TC")

      refute round.hearts_broken?
      assert_equal 1, round.to_act
      assert_equal ONLY_HEARTS_LEADER[1].drop(1), round.legal_moves(1)
      assert_accepted round.apply(1, Play.new(card: "2H"))
    end

    test "nothing can be played once the runde is complete" do
      round = play_out(round_for(MIXED))

      assert_equal :complete, round.phase
      assert_nil round.to_act
      assert_rejected :round_complete, round.apply(0, Play.new(card: "2C"))
      assert_equal [], round.legal_moves(0)
    end

    test "points are 1 per heart and 13 for Q♠ taken; one point spoils the moon" do
      # Seat 2 takes stik 1 with its only club (A♣) and one heart from seat 3.
      # Seat 0 then takes every other stik: A♠ wins stik 2, its clubs the rest.
      round = play_out(round_for(SPOILED_MOON))

      assert_equal [ 25, 0, 1, 0 ], round.points
      assert_nil round.moon_shooter
    end

    test "points are empty until the runde is complete" do
      assert_equal [], round_for(MIXED).points
    end

    test "taking all 26 points shoots the moon: the shooter scores 0, the others 26" do
      # Seat 0 holds every club, leads all 13 stik and wins them all.
      round = play_out(round_for(BY_SUIT))

      assert_equal 0, round.moon_shooter
      assert_equal [ 0, 26, 26, 26 ], round.points
    end

    test "deals with stored plays that break the rules are refused" do
      deal = Deal.new(hands: MIXED.map { |hand| hand.map { |code| Card.parse(code) } })

      assert_raises(ArgumentError) { Round.new(rules: Rules.standard, deal:, plays: %w[3C]) }
      assert_raises(ArgumentError) { Round.from_strings(rules: Rules.standard, deal: deal.to_s, plays: "2C QS") }
    end

    private

    def round_for(hands)
      Round.from_strings(rules: Rules.standard, deal: hands.flatten.join(" "), plays: "")
    end

    def play(round, *codes)
      codes.compact.reduce(round) do |current, code|
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
