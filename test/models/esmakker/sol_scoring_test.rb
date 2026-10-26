require "test_helper"

module Esmakker
  # The settlement of a sol-melding (REGLER §2.0 "Point"): each sol player
  # on her own against each modspiller, for the melding's fixed amount; no
  # doublings; zero-sum.
  class SolScoringTest < ActiveSupport::TestCase
    test "alone: she wins the amount from each of the three modspillere, or pays it to each" do
      assert_equal [ -3, 9, -3, -3 ], Scoring.sol_points(players: [ 1 ], vaeltet: [], amount: 3)
      assert_equal [ 3, -9, 3, 3 ], Scoring.sol_points(players: [ 1 ], vaeltet: [ 1 ], amount: 3)
    end

    test "several sol players are settled one by one with the modspillere, never with one another" do
      # Seat 1 clears, seat 2 is væltet: each settles with seats 0 and 3.
      assert_equal [ 0, 6, -6, 0 ], Scoring.sol_points(players: [ 1, 2 ], vaeltet: [ 2 ], amount: 3)
      assert_equal [ -6, 6, 6, -6 ], Scoring.sol_points(players: [ 1, 2 ], vaeltet: [], amount: 3)
      # Three sol players against one modspiller.
      assert_equal [ -4, 4, 4, -4 ], Scoring.sol_points(players: [ 1, 2, 3 ], vaeltet: [ 3 ], amount: 4)
      assert_equal [ 12, -4, -4, -4 ], Scoring.sol_points(players: [ 1, 2, 3 ], vaeltet: [ 1, 2, 3 ], amount: 4)
    end

    test "with all four playing the sol-melding there is no modspiller and nobody wins anything" do
      assert_equal [ 0, 0, 0, 0 ], Scoring.sol_points(players: [ 0, 1, 2, 3 ], vaeltet: [ 2 ], amount: 3)
    end

    test "the bord's amounts: sol and ren sol each their own, halves kept exact" do
      values = Points.from_h(sol: 2.5, ren_sol: 5)
      sol = SolResult.settled(melder: 0, melding: Melding.sol, players: [ 0 ], most_stik: 1, vaeltet: [], tricks_won: [ 1, 4, 4, 4 ], values:)
      ren = SolResult.settled(melder: 0, melding: Melding.ren_sol, players: [ 0 ], most_stik: 0, vaeltet: [ 0 ], tricks_won: [ 1, 0, 0, 0 ], values:)

      assert_equal [ 7.5, -2.5, -2.5, -2.5 ], sol.points
      assert_equal [ -15, 5, 5, 5 ], ren.points
      assert_equal [ 0, 0 ], [ sol.points.sum, ren.points.sum ]
    end
  end
end
