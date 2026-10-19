require "test_helper"

module Hjerterfri
  # Property-style checks over seeded random deals, playing random legal moves.
  class RoundReplayTest < ActiveSupport::TestCase
    REJECTIONS = %i[must_lead_two_of_clubs must_follow_suit no_points_on_first_trick hearts_not_broken].freeze

    test "random legal play always completes 13 stik with 26 points or a moon" do
      40.times do |seed|
        round = play_out(seed)

        assert round.complete?
        assert_equal 52, round.plays.size
        assert_equal (round.moon_shooter ? 78 : 26), round.points.sum, "seed #{seed}: #{round.points}"
      end
    end

    test "points match the penalty cards in the stik each seat won" do
      40.times do |seed|
        taken, round = [ 0 ] * 4, start(seed)
        round = step(round, Random.new(seed)).tap { |next_round| count_trick(next_round, taken) } until round.complete?

        expected = taken.include?(26) ? taken.map { |points| points == 26 ? 0 : 26 } : taken
        assert_equal expected, round.points, "seed #{seed}"
      end
    end

    test "every card outside the legal moves is rejected with a rule reason" do
      10.times do |seed|
        round, random = start(seed), Random.new(seed)
        until round.complete?
          seat = round.to_act
          illegal = round.view_for(seat)[:hand] - round.legal_moves(seat)
          illegal.each { |card| assert_includes REJECTIONS, round.apply(seat, Play.new(card:)).reason }
          round = step(round, random)
        end
      end
    end

    test "rebuilding from the stored strings equals live play at every step" do
      10.times do |seed|
        round, random = start(seed), Random.new(seed)
        loop do
          rebuilt = Round.from_strings(rules: Rules.standard, deal: round.deal_string, plays: round.plays_string)

          assert_equal round, rebuilt
          (0..3).each { |seat| assert_equal round.view_for(seat), rebuilt.view_for(seat) }
          break if round.complete?

          round = step(round, random)
        end
      end
    end

    private

    def start(seed) = Round.new(rules: Rules.standard, deal: Deal.shuffled(shuffler: Random.new(seed)))

    def play_out(seed)
      round, random = start(seed), Random.new(seed)
      round = step(round, random) until round.complete?
      round
    end

    def step(round, random)
      seat = round.to_act
      moves = round.legal_moves(seat)
      refute_empty moves
      result = round.apply(seat, Play.new(card: moves.sample(random:)))
      assert result.accepted?, result.reason.inspect
      result.round
    end

    def count_trick(round, taken)
      view = round.view_for(0)
      return unless view[:current_trick].empty?

      taken[view[:last_trick_winner]] += view[:last_trick].sum { |play| Card.parse(play[:card]).points }
    end
  end
end
