require "test_helper"

module Hjerterfri
  class RoundViewTest < ActiveSupport::TestCase
    setup do
      @deal = Deal.shuffled(shuffler: Random.new(42))
      @round = Round.new(rules: Rules.standard, deal: @deal)
    end

    test "shows the seat its own hand, sorted, and the opponents' card counts" do
      view = @round.view_for(1)
      sorted = @deal.hand(1).sort_by(&:display_key).map(&:to_s)

      assert_equal sorted, view[:hand]
      assert_equal({ 0 => 13, 2 => 13, 3 => 13 }, view[:card_counts])
      assert_equal :playing, view[:phase]
      refute view[:hearts_broken]
      assert_equal [], view[:points]
    end

    test "legal moves are shown only to the seat to act" do
      leader = @round.to_act

      assert_equal [ "2C" ], @round.view_for(leader)[:legal_moves]
      (0..3).excluding(leader).each { |seat| assert_equal [], @round.view_for(seat)[:legal_moves] }
    end

    test "shows the current stik with seats, then the last completed stik" do
      leader = @round.to_act
      round = play_random(@round, 3)

      current = round.view_for(0)[:current_trick]
      assert_equal [ leader, (leader + 1) % 4, (leader + 2) % 4 ], current.map { |play| play[:seat] }
      assert_equal "2C", current.first[:card]
      assert_equal [], round.view_for(0)[:last_trick]

      round = play_random(round, 1)
      view = round.view_for(0)
      assert_equal [], view[:current_trick]
      assert_equal 4, view[:last_trick].size
      assert_equal view[:to_act], view[:last_trick_winner]
    end

    test "shows every completed stik of the runde, the points taken and the rules" do
      round = play_random(@round, 9)
      view = round.view_for(3)

      assert_equal 2, view[:tricks].size
      assert_equal "2C", view[:tricks].first[:plays].first[:card]
      assert_equal round.plays_string.split.first(8), view[:tricks].flat_map { |trick| trick[:plays].map { |play| play[:card] } }
      assert_equal view[:tricks].last[:winner], view[:last_trick_winner]
      assert_equal round.points_taken, view[:points_taken]
      assert_equal Rules.standard.to_h, view[:rules]
    end

    test "never includes a card another seat still holds" do
      round = @round
      52.times do
        (0..3).each { |seat| assert_no_hidden_cards(round, seat) }
        round = play_random(round, 1)
      end
      (0..3).each { |seat| assert_no_hidden_cards(round, seat) }
    end

    test "a complete runde shows points and no seat to act" do
      view = play_random(@round, 52).view_for(2)

      assert_equal :complete, view[:phase]
      assert_nil view[:to_act]
      assert_equal [], view[:hand]
      assert_equal 4, view[:points].size
    end

    private

    def play_random(round, count, random: Random.new(count))
      count.times.reduce(round) do |current, _|
        card = current.legal_moves(current.to_act).sample(random:)
        current.apply(current.to_act, Play.new(card:)).round
      end
    end

    def assert_no_hidden_cards(round, seat)
      played = round.plays_string.split
      hidden = (0..3).excluding(seat).flat_map { |other| @deal.hand(other).map(&:to_s) } - played
      shown = round.view_for(seat).to_s.scan(/\b[2-9TJQKA][CDHS]\b/)

      assert_empty shown & hidden, "seat #{seat} sees another seat's cards"
    end
  end
end
