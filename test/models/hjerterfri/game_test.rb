require "test_helper"

module Hjerterfri
  class GameTest < ActiveSupport::TestCase
    test "a new spil has no runder, zero totals and starts with runde 1 passing left" do
      game = Game.new(rules: Rules.standard)

      assert_equal [ 0, 0, 0, 0 ], game.totals
      assert_equal [], game.rows
      refute game.over?
      assert_equal [], game.winners
      assert_equal 1, game.next_runde_number
      assert_equal :left, game.next_pass_direction
    end

    test "the score sheet has one row per runde with running totals" do
      game = Game.new(rules: Rules.standard, results: [ [ 3, 13, 10, 0 ], [ 0, 26, 26, 26 ], [ 5, 5, 6, 10 ] ])

      assert_equal [ 8, 44, 42, 36 ], game.totals
      assert_equal [
        { number: 1, pass_direction: :left, points: [ 3, 13, 10, 0 ], totals: [ 3, 13, 10, 0 ] },
        { number: 2, pass_direction: :right, points: [ 0, 26, 26, 26 ], totals: [ 3, 39, 36, 26 ] },
        { number: 3, pass_direction: :across, points: [ 5, 5, 6, 10 ], totals: [ 8, 44, 42, 36 ] }
      ], game.rows
    end

    test "runde numbers and pass directions continue across the spil, wrapping after runde 4" do
      game = Game.new(rules: Rules.standard)
      directions = 8.times.map do
        direction = game.next_pass_direction
        game = game.add([ 1, 1, 1, 1 ])
        direction
      end

      assert_equal %i[left right across none left right across none], directions
      assert_equal 9, game.next_runde_number
      assert_equal (1..8).to_a, game.rows.map { |row| row[:number] }
    end

    test "adding runder one by one equals building from the stored results" do
      results = [ [ 3, 13, 10, 0 ], [ 0, 26, 26, 26 ] ]
      built = results.reduce(Game.new(rules: Rules.standard)) { |game, points| game.add(points) }

      assert_equal Game.new(rules: Rules.standard, results:), built
    end

    test "the spil is not over below the end score" do
      game = Game.new(rules: Rules.standard, results: [ [ 99, 0, 0, 0 ] ])

      refute game.over?
      assert_equal [], game.winners
      assert_equal 2, game.next_runde_number
    end

    test "the spil is over when a seat reaches the end score, and the lowest total wins" do
      game = Game.new(rules: Rules.standard, results: [ [ 90, 20, 5, 30 ], [ 10, 0, 1, 0 ] ])

      assert game.over?
      assert_equal [ 100, 20, 6, 30 ], game.totals
      assert_equal [ 2 ], game.winners
      assert_nil game.next_runde_number
      assert_nil game.next_pass_direction
    end

    test "ties for the lowest total share the win" do
      game = Game.new(rules: Rules.standard, results: [ [ 104, 12, 30, 12 ] ])

      assert_equal [ 1, 3 ], game.winners
    end

    test "the end score comes from the rules" do
      game = Game.new(rules: Rules.new(end_score: 50), results: [ [ 50, 10, 20, 0 ] ])

      assert game.over?
      assert_equal [ 3 ], game.winners
      refute Game.new(rules: Rules.standard, results: game.results).over?
    end

    test "J♦ can take totals below zero" do
      game = Game.new(rules: Rules.new(jack_of_diamonds_minus_ten: true), results: [ [ -10, 26, 26, 26 ], [ 0, 26, 26, 26 ] ])

      assert_equal [ -10, 52, 52, 52 ], game.totals
    end

    test "no runde can be added once the spil is over" do
      game = Game.new(rules: Rules.standard, results: [ [ 100, 0, 0, 0 ] ])

      assert_raises(ArgumentError) { game.add([ 1, 1, 1, 1 ]) }
    end

    test "refuses results that are not four integer scores" do
      [ [ [ 1, 2, 3 ] ], [ [ 1, 2, 3, "4" ] ], [ nil ] ].each do |results|
        assert_raises(ArgumentError) { Game.new(rules: Rules.standard, results:) }
      end
    end
  end
end
