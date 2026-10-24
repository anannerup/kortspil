require "test_helper"

module Hjerterfri
  # The house-rule toggles (docs/rules §3.9, ticket 09), each on and off,
  # and shooter's choice.
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

    test "the standard preset has every toggle off" do
      refute Rules.standard.queen_breaks_hearts
      refute Rules.standard.jack_of_diamonds_minus_ten
      refute Rules.standard.shooters_choice
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

    test "with J♦ −10 on, points taken count J♦ as soon as its stik is taken" do
      round = play(round_for(MOON_WITHOUT_JACK, Rules.new(jack_of_diamonds_minus_ten: true)), "2C", "AC", "JD", "3S")

      assert_equal [ 0, -10, 0, 0 ], round.points_taken
      assert_equal [ 0, 0, 0, 0 ], play(round_for(MOON_WITHOUT_JACK, Rules.standard), "2C", "AC", "JD", "3S").points_taken
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

    test "J♦ −10 does not apply to a moon shooter who took J♦" do
      round = play_out(round_for(BY_SUIT, Rules.new(jack_of_diamonds_minus_ten: true)))

      assert_equal 0, round.moon_shooter
      assert_equal 0, round.jack_of_diamonds_taker
      assert_equal [ 0, 26, 26, 26 ], round.points
    end

    test "the standard preset has shooter's choice off: the moon always gives 26 to everyone else" do
      refute Rules.standard.shooters_choice
      round = play_out(round_for(BY_SUIT, Rules.standard))

      assert_equal :complete, round.phase
      assert_equal [ 0, 26, 26, 26 ], round.points
      assert_equal :round_complete, round.apply(0, MoonChoice.new(option: "subtract_from_self")).reason
    end

    test "with shooter's choice on, the shooter chooses before the runde is complete" do
      round = play_out(round_for(BY_SUIT, Rules.new(shooters_choice: true)))

      assert_equal :choosing_moon, round.phase
      refute round.complete?
      assert_equal 0, round.to_act
      assert_equal 0, round.moon_shooter
      assert_equal [], round.points
      assert_equal [], round.legal_moves(0)
      assert_equal :choosing_moon, round.view_for(1)[:phase]
      assert_nil round.view_for(1)[:moon_choice]
    end

    test "with shooter's choice on, the shooter can give 26 to everyone else" do
      round = choose(play_out(round_for(BY_SUIT, Rules.new(shooters_choice: true))), 0, "add_to_others")

      assert round.complete?
      assert_equal "add_to_others", round.moon_choice
      assert_equal [ 0, 26, 26, 26 ], round.points
      assert_equal "add_to_others", round.view_for(2)[:moon_choice]
    end

    test "with shooter's choice on, the shooter can take −26 themselves" do
      round = choose(play_out(round_for(BY_SUIT, Rules.new(shooters_choice: true))), 0, "subtract_from_self")

      assert_equal [ -26, 0, 0, 0 ], round.points
    end

    test "with −26 to the shooter, J♦ −10 still applies to another seat that took it" do
      rules = Rules.new(shooters_choice: true, jack_of_diamonds_minus_ten: true)
      round = play_out(play(round_for(MOON_WITHOUT_JACK, rules), "2C", "AC", "JD", "3S"))
      round = choose(round, 0, "subtract_from_self")

      assert_equal [ -26, -10, 0, 0 ], round.points
    end

    test "only the shooter may choose, only a known option, and only once" do
      round = play_out(round_for(BY_SUIT, Rules.new(shooters_choice: true)))

      assert_equal :not_your_turn, round.apply(1, MoonChoice.new(option: "add_to_others")).reason
      assert_equal :unknown_moon_choice, round.apply(0, MoonChoice.new(option: "both")).reason
      assert_equal :choosing_moon, round.apply(0, Play.new(card: "2C")).reason
      assert_equal :round_complete, choose(round, 0, "add_to_others").apply(0, MoonChoice.new(option: "subtract_from_self")).reason

      playing = round_for(BY_SUIT, Rules.new(shooters_choice: true))
      assert_equal :not_choosing_moon, playing.apply(0, MoonChoice.new(option: "add_to_others")).reason
    end

    test "with shooter's choice on, a runde without a moon needs no choice" do
      rules = Rules.new(shooters_choice: true)
      round = play_out(Round.new(rules:, deal: Deal.shuffled(shuffler: Random.new(3))))

      assert_nil round.moon_shooter
      assert round.complete?
    end

    test "the moon choice round-trips through the stored strings" do
      rules = Rules.new(shooters_choice: true)
      round = choose(play_out(round_for(BY_SUIT, rules)), 0, "subtract_from_self")
      rebuilt = Round.from_strings(rules:, deal: round.deal_string, plays: round.plays_string, moon_choice: round.moon_choice)

      assert_equal round, rebuilt
      assert_equal [ -26, 0, 0, 0 ], rebuilt.points
      assert_equal :choosing_moon, Round.from_strings(rules:, deal: round.deal_string, plays: round.plays_string, moon_choice: "").phase
    end

    test "a stored moon choice is refused without shooter's choice, without a moon or when unknown" do
      moon = play_out(round_for(BY_SUIT, Rules.standard))
      no_moon = play_out(Round.new(rules: Rules.standard, deal: Deal.shuffled(shuffler: Random.new(3))))
      on = Rules.new(shooters_choice: true)

      assert_raises(ArgumentError) { Round.from_strings(rules: Rules.standard, deal: moon.deal_string, plays: moon.plays_string, moon_choice: "add_to_others") }
      assert_raises(ArgumentError) { Round.from_strings(rules: on, deal: no_moon.deal_string, plays: no_moon.plays_string, moon_choice: "add_to_others") }
      assert_raises(ArgumentError) { Round.from_strings(rules: on, deal: moon.deal_string, plays: moon.plays_string, moon_choice: "both") }
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

    def choose(round, seat, option)
      result = round.apply(seat, MoonChoice.new(option:))
      assert result.accepted?, "#{option} was rejected: #{result.reason}"
      result.round
    end

    def play_out(round)
      round = play(round, round.legal_moves(round.to_act).first) until round.all_tricks_played?
      round
    end
  end
end
