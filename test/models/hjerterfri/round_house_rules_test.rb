require "test_helper"

module Hjerterfri
  # The house-rule toggles (docs/rules §3.9, ticket 09), each on and off.
  class RoundHouseRulesTest < ActiveSupport::TestCase
    # Stik 1 goes to seat 3 (3♣ over 2♣). Seat 3 leads 2♠ and seat 1 must
    # follow with Q♠, its only spade, which takes the stik. No heart has
    # been played when seat 1 leads stik 3, holding diamonds and hearts.
    QUEEN_BEFORE_HEARTS = [
      %w[2C 4C 5C 6C 7C 8C 9C TC JC QC KC AC AH],
      %w[QS 2D 3D 4D 5D 6D 7D 2H 3H 4H 5H 6H 7H],
      %w[8D 9D TD JD QD KD AD 8H 9H TH JH QH KH],
      %w[3C 2S 3S 4S 5S 6S 7S 8S 9S TS JS KS AS]
    ]
    QUEEN_BEFORE_HEARTS_PLAYS = %w[2C 2D 8D 3C 2S 4C QS 9D]

    # Each seat holds one whole suit: seat 0 (clubs) wins every stik, J♦ included.
    BY_SUIT = %w[C D S H].map { |suit| Card::RANKS.map { |rank| "#{rank}#{suit}" } }

    # Seat 1 takes stik 1 with A♣ and the J♦ seat 2 must discard. Seat 0
    # wins A♦ on stik 2 and every club lead after, taking all 26 points.
    MOON_WITHOUT_JACK = [
      %w[2C 3C 4C 5C 6C 7C 8C 9C TC JC QC KC AD],
      %w[AC 2D 3D 4D 5D 6D 7D 8D 9D TD QD KD 2S],
      %w[JD QS 2H 3H 4H 5H 6H 7H 8H 9H TH JH QH],
      %w[KH AH 3S 4S 5S 6S 7S 8S 9S TS JS KS AS]
    ]

    test "the standard preset has both toggles off" do
      refute Rules.standard.queen_breaks_hearts
      refute Rules.standard.jack_of_diamonds_minus_ten
    end

    test "with Q♠-breaks-hearts off, playing Q♠ does not break hearts" do
      round = play(round_for(QUEEN_BEFORE_HEARTS, Rules.standard), *QUEEN_BEFORE_HEARTS_PLAYS)

      assert_equal 1, round.to_act
      refute round.hearts_broken?
      refute_includes round.legal_moves(1), "2H"
      assert_equal :hearts_not_broken, round.apply(1, Play.new(card: "2H")).reason
    end

    test "with Q♠-breaks-hearts on, playing Q♠ breaks hearts" do
      rules = Rules.new(queen_breaks_hearts: true)
      round = round_for(QUEEN_BEFORE_HEARTS, rules)
      round = play(round, *QUEEN_BEFORE_HEARTS_PLAYS.first(6))
      refute round.hearts_broken?, "not broken before Q♠ is played"

      round = play(round, *QUEEN_BEFORE_HEARTS_PLAYS.drop(6))
      assert round.hearts_broken?
      assert round.view_for(0)[:hearts_broken]
      assert_includes round.legal_moves(1), "2H"
      assert round.apply(1, Play.new(card: "2H")).accepted?
    end

    test "with J♦ −10 off, J♦ scores nothing" do
      round = play_out(round_for(MOON_WITHOUT_JACK, Rules.standard))

      assert_nil round.jack_of_diamonds_taker
      assert_equal [ 0, 26, 26, 26 ], round.points
    end

    test "with J♦ −10 on, whoever takes J♦ scores −10 for the runde" do
      rules = Rules.new(jack_of_diamonds_minus_ten: true)
      deal = Deal.shuffled(shuffler: Random.new(3))
      standard = play_out(Round.new(rules: Rules.standard, deal:))
      round = play_out(Round.new(rules:, deal:))
      taker = round.jack_of_diamonds_taker

      assert_nil standard.moon_shooter
      assert_equal standard.points.each_with_index.map { |points, seat| seat == taker ? points - 10 : points }, round.points
      assert_equal 16, round.points.sum
      assert_equal taker, round.view_for(0)[:jack_of_diamonds_taker]
    end

    test "J♦ −10 is nothing until the runde is complete" do
      round = round_for(BY_SUIT, Rules.new(jack_of_diamonds_minus_ten: true))

      assert_nil round.jack_of_diamonds_taker
      assert_equal [], round.points
    end

    test "the moon is judged on the 26 penalty points; J♦ −10 applies on top to another seat" do
      round = play_out(play(round_for(MOON_WITHOUT_JACK, Rules.new(jack_of_diamonds_minus_ten: true)), "2C", "AC", "JD", "3S"))

      assert_equal 0, round.moon_shooter
      assert_equal 1, round.jack_of_diamonds_taker
      assert_equal [ 0, 16, 26, 26 ], round.points
    end

    test "a moon shooter who also takes J♦ scores −10" do
      standard = play_out(round_for(BY_SUIT, Rules.standard))
      round = play_out(round_for(BY_SUIT, Rules.new(jack_of_diamonds_minus_ten: true)))

      assert_equal [ 0, 26, 26, 26 ], standard.points
      assert_equal 0, round.moon_shooter
      assert_equal [ -10, 26, 26, 26 ], round.points
    end

    private

    def round_for(hands, rules)
      Round.from_strings(rules:, deal: hands.flatten.join(" "), plays: "")
    end

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
  end
end
