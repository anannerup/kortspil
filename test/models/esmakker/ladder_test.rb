require "test_helper"

module Esmakker
  class LadderTest < ActiveSupport::TestCase
    test "the standard ladder is Anders's order with vip > halve > gode" do
      expected = %w[
        8 8gode 8halve 8vip
        9 9gode 9halve 9vip sol
        10 10gode 10halve 10vip ren_sol
        11 11gode 11halve 11vip bordlaegger
        12 12gode 12halve 12vip ren_bordlaegger
        13 13gode 13halve 13vip
      ]

      assert_equal expected, codes(Ladder.standard.meldinger)
    end

    test "the påhæng on one number follow the bord's order, lowest first on the ladder" do
      ladder = Ladder.new(pahaeng_order: %w[gode vip halve])

      assert_equal %w[9 9halve 9vip 9gode sol 10], codes(ladder.meldinger[4, 6])
    end

    test "a påhæng the bord leaves out is not on the ladder" do
      ladder = Ladder.new(pahaeng_order: %i[vip gode])

      assert_equal %w[8 8gode 8vip 9 9gode 9vip sol], codes(ladder.meldinger.first(7))
      assert_not ladder.include?(Melding.stik(8, :halve))
      assert_raises(ArgumentError) { ladder.rank(Melding.stik(8, :halve)) }
    end

    test "a bord without påhæng has numbers and nolo only" do
      ladder = Ladder.new(pahaeng_order: [])

      assert_equal %w[8 9 sol 10 ren_sol 11 bordlaegger 12 ren_bordlaegger 13], codes(ladder.meldinger)
    end

    test "unknown or repeated påhæng are refused" do
      assert_raises(ArgumentError) { Ladder.new(pahaeng_order: %i[vip staerke]) }
      assert_raises(ArgumentError) { Ladder.new(pahaeng_order: %i[vip vip]) }
    end

    test "compare and higher? follow the ladder" do
      ladder = Ladder.standard

      assert_equal(-1, ladder.compare(Melding.stik(9, :vip), Melding.sol))
      assert_equal 1, ladder.compare(Melding.stik(10), Melding.sol)
      assert_equal 0, ladder.compare(Melding.ren_sol, Melding.ren_sol)
      assert ladder.higher?(Melding.stik(8, :vip), Melding.stik(8, :gode))
      assert ladder.higher?(Melding.stik(11), Melding.stik(10, :vip))
      assert ladder.higher?(Melding.bordlaegger, Melding.stik(11, :vip))
    end

    test "above gives the legal bids over a melding, and the whole ladder over nothing" do
      ladder = Ladder.standard

      assert_equal %w[13 13gode 13halve 13vip], codes(ladder.above(Melding.ren_bordlaegger))
      assert_equal [], ladder.above(ladder.highest)
      assert_equal ladder.meldinger, ladder.above(nil)
      assert_equal Melding.stik(8), ladder.lowest
    end

    private

    def codes(meldinger) = meldinger.map(&:to_s)
  end
end
