require "test_helper"

module Esmakker
  # Seam 1 for ticket 05: what a runde scores (RundeResult#points, by
  # Scoring) against REGLER §2.0 "Point" and its lookup table.
  #
  # Seat 1 is melder throughout; seat 3 the esmakker unless she is
  # selvmakker. The side's stik are given to seat 1, the rest spread.
  class ScoringTest < ActiveSupport::TestCase
    # REGLER §2.0 "Opslagstabel": the amount per loser and winner for a
    # melding that goes home, exactly (præcis) and with 1–5 overstik; "p" is
    # with påhæng. nil where the overstik cannot be taken (13 stik at most).
    LOOKUP = {
      "8" => [ 1, 2, 3, 4, 5, 6 ],
      "8p" => [ 2, 4, 6, 8, 10, 12 ],
      "9" => [ 1.5, 2.5, 3.5, 4.5, 5.5, nil ],
      "9p" => [ 3, 5, 7, 9, 11, nil ],
      "10" => [ 2, 3, 4, 5, nil, nil ],
      "10p" => [ 4, 6, 8, 10, nil, nil ],
      "11" => [ 2.5, 3.5, 4.5, nil, nil, nil ],
      "11p" => [ 5, 7, 9, nil, nil, nil ],
      "12" => [ 3, 4, nil, nil, nil, nil ],
      "12p" => [ 6, 8, nil, nil, nil, nil ],
      "13" => [ 3.5, nil, nil, nil, nil, nil ],
      "13p" => [ 7, nil, nil, nil, nil, nil ]
    }.freeze

    test "every cell of REGLER's lookup table, at gode and at halve for the p rows, two against two" do
      LOOKUP.each do |row, cells|
        number = row.to_i
        pahaengs = row.end_with?("p") ? %i[gode halve] : [ nil ]
        pahaengs.each do |pahaeng|
          cells.each_with_index do |cell, over|
            next if cell.nil?

            assert_operator number + over, :<=, 13
            points = result(melding: Melding.stik(number, pahaeng), stik: number + over).points
            assert_equal [ -2 * cell, 2 * cell, -2 * cell, 2 * cell ], points, "#{row}#{pahaeng} +#{over}: each winner gets #{cell} from each loser"
          end
        end
      end
    end

    test "the lookup table's dashes are the overstik that cannot be taken" do
      LOOKUP.each do |row, cells|
        assert_equal [ 6, 14 - row.to_i ].min, cells.compact.size, row
      end
    end

    test "bet loses the stake per missing stik, 1–3 missing" do
      { 1 => 2.5, 2 => 5, 3 => 7.5 }.each do |missing, amount|
        points = result(melding: Melding.stik(11), stik: 11 - missing).points
        assert_equal [ 2 * amount, -2 * amount, 2 * amount, -2 * amount ], points, "11 with #{missing} missing"
      end
      assert_equal [ 2, -2, 2, -2 ], result(melding: Melding.stik(8), stik: 7).points
      assert_equal [ 6, -6, 6, -6 ], result(melding: Melding.stik(8), stik: 5).points
    end

    test "påhæng and trumfløs each double, at home and bet, and together quadruple" do
      assert_equal [ -4, 4, -4, 4 ], result(melding: Melding.stik(8, :gode), stik: 8).points
      assert_equal [ -4, 4, -4, 4 ], result(melding: Melding.stik(8), stik: 8, trump: Trump.trumfloes).points
      assert_equal [ -8, 8, -8, 8 ], result(melding: Melding.stik(8, :halve), stik: 8, trump: Trump.trumfloes).points
      assert_equal [ -20, 20, -20, 20 ], result(melding: Melding.stik(9, :halve), stik: 10, trump: Trump.trumfloes).points, "(1.5 + 1) × 2 × 2"
    end

    test "the doublings multiply into bet as well" do
      assert_equal [ 48, -48, 48, -48 ], result(melding: Melding.stik(10, :gode), stik: 7, trump: Trump.trumfloes).points, "2 × 3 missing × 2 × 2 = 24 per pair"
    end

    test "vip is scored by its kitty card alone, and each bank doubles (hooks for tickets 07 and 08)" do
      vip = Melding.stik(10, :vip)
      assert_equal [ -8, 8, -8, 8 ], result(melding: vip, stik: 10, vip_card: 1).points, "vip with the first card is 10p: 4 per pair"
      assert_equal [ -16, 16, -16, 16 ], result(melding: vip, stik: 10, vip_card: 2).points
      assert_equal [ -32, 32, -32, 32 ], result(melding: vip, stik: 10, vip_card: 3).points
      assert_equal [ 32, -32, 32, -32 ], result(melding: vip, stik: 9, vip_card: 1, banks: 2).points, "2 × 1 missing × 2 × 2 × 2 per pair"
      assert_raises(ArgumentError) { result(melding: vip, stik: 10) }
      assert_equal [ -8, 8, -8, 8 ], result(melding: Melding.stik(10), stik: 10, banks: 1).points, "2 × 2 per bank"
    end

    test "a selvmakker wins from, or loses to, each of the three others" do
      home = result(melding: Melding.stik(9), stik: 10, esmakker: nil)
      assert_equal [ -2.5, 7.5, -2.5, -2.5 ], home.points
      bet = result(melding: Melding.stik(9, :gode), stik: 7, esmakker: nil)
      assert_equal [ 6, -18, 6, 6 ], bet.points
    end

    test "every runde sums to zero, whatever the values" do
      values = Points.from_h(stakes: { "8" => 0.3, "9" => 1.25 }, pahaeng: 3, trumflos: 1.5, bank: 2.5, vip_first: 1.1)
      melding_codes = %w[8 8gode 9 9halve 10 11gode 12 13 13halve 10vip]
      melding_codes.each do |code|
        melding = Melding.parse(code)
        (0..13).each do |stik|
          [ 3, nil ].each do |esmakker|
            [ Trump.parse("H"), Trump.trumfloes ].each do |trump|
              points = result(melding:, stik:, esmakker:, trump:, values:, vip_card: (1 if melding.pahaeng == :vip), banks: stik % 3).points
              assert_equal 0, points.sum { |amount| Scoring.exact(amount) }, "#{code} #{stik} stik #{esmakker.inspect} #{trump}: #{points}"
            end
          end
        end
      end
    end

    test "the bord's own point values are the ones scored with" do
      values = Points.from_h(stakes: { "8" => 5, "10" => 0.5 }, pahaeng: 3, trumflos: 10)
      assert_equal [ -10, 10, -10, 10 ], result(melding: Melding.stik(8), stik: 8, values:).points
      assert_equal [ -42, 42, -42, 42 ], result(melding: Melding.stik(8, :gode), stik: 10, values:).points, "(5 + 2) × 3"
      assert_equal [ 30, -30, 30, -30 ], result(melding: Melding.stik(10), stik: 7, values:, trump: Trump.trumfloes).points, "0.5 × 3 × 10"
      assert_equal [ -0.6, 0.6, -0.6, 0.6 ], result(melding: Melding.stik(8), stik: 8, values: Points.from_h(stakes: { "8" => 0.3 })).points
    end

    test "a melding not played scores nothing" do
      assert_equal [ 0, 0, 0, 0 ], RundeResult.not_played(melder: 1, melding: Melding.parse("9halve")).points
    end

    test "totals are the exact running sum, and the highest total leads" do
      values = Points.from_h(stakes: { "8" => 0.1 })
      results = [ result(melding: Melding.stik(8), stik: 8, values:), result(melding: Melding.stik(8), stik: 8, values:, esmakker: 2),
                  result(melding: Melding.stik(8), stik: 8, values:) ]
      game = Game.new(rules: Rules.new(points: values), runder: 5, results:)

      assert_equal [ -0.6, 0.6, -0.2, 0.2 ], game.totals
      assert_equal [ [ -0.2, 0.2, -0.2, 0.2 ], [ -0.4, 0.4, 0, 0 ], [ -0.6, 0.6, -0.2, 0.2 ] ], game.running_totals
      assert_equal [ 1 ], game.leaders
      assert_empty Game.new(rules: Rules.standard, runder: 5).leaders
      assert_equal [ 0, 0, 0, 0 ], Game.new(rules: Rules.standard, runder: 5).totals
    end

    private

    # A played stik melding by seat 1 with `stik` for her side; seat 3 is
    # the esmakker unless `esmakker` says otherwise (nil: selvmakker).
    def result(melding:, stik:, esmakker: 3, trump: Trump.parse("S"), values: Points.standard, vip_card: nil, banks: 0)
      others = Seats::ALL - [ 1, esmakker ].compact
      rest = 13 - stik
      tricks_won = [ 0 ] * 4
      tricks_won[1] = stik
      others.each_with_index { |seat, index| tricks_won[seat] = (rest / others.size) + (index < rest % others.size ? 1 : 0) }
      RundeResult.played(melder: 1, melding:, trump:, called_ace: "D", esmakker:, selvmakker: esmakker.nil?, tricks_won:, values:, vip_card:, banks:)
    end
  end
end
