require "test_helper"

module Esmakker
  class MeldingTest < ActiveSupport::TestCase
    test "a melding is 8–13 with at most one påhæng, or a nolo melding" do
      assert_equal "9vip", Melding.stik(9, :vip).to_s
      assert_equal "13", Melding.stik(13).to_s
      assert Melding.sol.nolo?
      assert Melding.stik(8).stik?
    end

    test "nothing below 8, no stærke, no suit meldinger, no trumfløs" do
      assert_raises(ArgumentError) { Melding.stik(7) }
      assert_raises(ArgumentError) { Melding.stik(14) }
      assert_raises(ArgumentError) { Melding.stik(9, :staerke) }
      assert_raises(ArgumentError) { Melding.stik(9, :sans) }
      assert_raises(ArgumentError) { Melding.nolo(:spar) }
      assert_raises(ArgumentError) { Melding.parse("trumfloes") }
    end

    test "codes round-trip" do
      Ladder.standard.meldinger.each { |melding| assert_equal melding, Melding.parse(melding.to_s) }
      assert_raises(ArgumentError) { Melding.parse("9 vip") }
    end
  end
end
