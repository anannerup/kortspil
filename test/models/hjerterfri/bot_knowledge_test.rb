require "test_helper"

module Hjerterfri
  class BotKnowledgeTest < ActiveSupport::TestCase
    test "every level places Q♠ when all other seats but one have shown out of spades" do
      # Spades led twice: seat 2 and seat 3 threw off other suits.
      tricks = [ trick(%w[3S 4S 5D 6C], leader: 0, winner: 1), trick(%w[7S 8S 9H TC], leader: 1, winner: 2) ]

      Bot::LEVELS.each do |level|
        assert_equal 1, knowing(level, hand: %w[2S 9S TS JS 2C 3C 4C], tricks:).queen_holder, level
      end
    end

    test "Mellem and Svær remember who they passed Q♠ to" do
      view = { own_pass: %w[QS 2H 3H], pass_direction: :right }

      assert_nil knowing(:let, hand: %w[2C 3C], **view).queen_holder
      assert_equal 3, knowing(:mellem, hand: %w[2C 3C], **view).queen_holder
      assert_equal 3, knowing(:svaer, hand: %w[2C 3C], **view).queen_holder
    end

    test "Svær finds a void more likely as a suit is played out" do
      early = [ trick(%w[2D 3D 4D 5D], leader: 1, winner: 0) ]
      late = early + [ trick(%w[6D 7D 8D 9D], leader: 0, winner: 3), trick(%w[TD JD QD 2C], leader: 3, winner: 1) ]
      hand = %w[AD 3C 4C 5C 6C 7C 8C 9C TC]

      after_one = knowing(:svaer, hand:, tricks: early, card_counts: { 1 => 12, 2 => 12, 3 => 12 }).void_odds(2, "D")
      after_three = knowing(:svaer, hand:, tricks: late, card_counts: { 1 => 10, 2 => 10, 3 => 10 }).void_odds(2, "D")

      assert_operator after_one, :<, 0.5
      assert_operator after_three, :>, after_one
    end

    test "Svær doubts Q♠ is with a seat that threw off another card instead" do
      # Seat 2 was void in clubs and threw a heart, not Q♠.
      tricks = [ trick(%w[2C 5C 9H 7C], leader: 0, winner: 3) ]
      odds = knowing(:svaer, hand: %w[2S 3S 4S 8C], tricks:, card_counts: { 1 => 12, 2 => 12, 3 => 12 }).queen_odds

      assert_operator odds[2], :<, odds[1]
      assert_operator odds[2], :<, odds[3]
    end

    test "the same risk measure grows with what has been played, in any suit" do
      hand = %w[AD 3C 4C 5C 6C 7C 8C 9C TC 2S 3S]
      early = [ trick(%w[2D 3D 4D 5D], leader: 1, winner: 0) ]
      late = early + [ trick(%w[6D 7D 8D 9D], leader: 0, winner: 3), trick(%w[TD JD KH QD], leader: 3, winner: 1) ]

      refute knowing(:svaer, hand:, tricks: early, card_counts: { 1 => 12, 2 => 12, 3 => 12 }).risky?("D")
      assert knowing(:svaer, hand:, tricks: late, card_counts: { 1 => 10, 2 => 10, 3 => 10 }).risky?("D")
    end

    test "a seat that threw off instead of dropping Q♠ is less likely to have it, from Mellem up" do
      tricks = [ trick(%w[2C 5C 9H 7C], leader: 0, winner: 3) ]

      let = knowing(:let, hand: %w[2S 3S 4S 8C], tricks:).queen_odds
      mellem = knowing(:mellem, hand: %w[2S 3S 4S 8C], tricks:).queen_odds
      assert_equal let[1], let[2]
      assert_operator mellem[2], :<, mellem[1]
    end

    test "Let sees risk only once a seat has shown out; Mellem and Svær see it coming" do
      hand = %w[AD 3C 4C 5C 6C 7C 8C 9C TC 2S 3S]
      tricks = [ trick(%w[2D 3D 4D 5D], leader: 1, winner: 0), trick(%w[6D 7D 8D 9D], leader: 0, winner: 3), trick(%w[TD JD QD KD], leader: 3, winner: 2) ]
      counts = { 1 => 10, 2 => 10, 3 => 10 }

      refute knowing(:let, hand:, tricks:, card_counts: counts).risky?("D")
      assert knowing(:mellem, hand:, tricks:, card_counts: counts).risky?("D")
      assert knowing(:svaer, hand:, tricks:, card_counts: counts).risky?("D")
    end

    test "the giver of several cards of a suit is likely void in it, from the second stik on" do
      hand = %w[9C JD QD KD 8S 9S TS 5H 6H 7H 8H 9H]
      first = { own_pass: %w[AH KH AS], received_cards: %w[JD QD KD], card_counts: { 1 => 12, 2 => 12, 3 => 12 } }
      second = first.merge(tricks: [ trick(%w[2C 3C 4C 5C], leader: 2, winner: 1) ], card_counts: { 1 => 12, 2 => 12, 3 => 12 })

      refute knowing(:svaer, hand:, **first).risky?("D"), "the first stik carries no points"
      svaer = knowing(:svaer, hand:, **second)
      assert svaer.risky?("D")
      assert_operator svaer.void_odds(3, "D"), :>=, 0.4
      assert_operator svaer.void_odds(3, "D"), :>, knowing(:svaer, hand:, **second, received_cards: %w[2C 3C 4C]).void_odds(3, "D")
    end

    test "Mellem treats a giver of 2+ cards of a suit as likely void; Let ignores the pass" do
      hand = %w[9C JD QD 8S 9S TS 5H 6H 7H 8H 9H 2D]
      view = { own_pass: %w[AH KH AS], received_cards: %w[JD QD 2D], tricks: [ trick(%w[2C 3C 4C 5C], leader: 2, winner: 1) ] }

      assert_operator knowing(:mellem, hand:, **view).void_odds(3, "D"), :>=, 0.5
      assert_equal 0.0, knowing(:let, hand:, **view).void_chance(3, "D")
    end

    test "a seat that has followed a suit is no longer suspected void in it from the pass" do
      hand = %w[9C JD QD KD 8S 9S TS 5H 6H 7H 8H 9H]
      tricks = [ trick(%w[2C 3C 4C 5C], leader: 2, winner: 1), trick(%w[2D 3D 4D 5D], leader: 1, winner: 1) ]
      view = { own_pass: %w[AH KH AS], received_cards: %w[JD QD KD], tricks:, card_counts: { 1 => 11, 2 => 11, 3 => 11 } }

      assert_operator knowing(:svaer, hand:, **view).void_odds(3, "D"), :<, 0.1
    end

    private

    def knowing(level, hand:, tricks: [], own_pass: [], received_cards: [], pass_direction: :left, card_counts: { 1 => 13, 2 => 13, 3 => 13 })
      view = { seat: 0, hand:, legal_moves: hand, current_trick: [], tricks:, rules: Rules.standard.to_h, own_pass:, received_cards:, pass_direction:, card_counts: }
      Bot::Knowledge.new(view, level:)
    end

    def trick(cards, leader:, winner:)
      { plays: cards.each_with_index.map { |card, index| { seat: (leader + index) % 4, card: } }, winner: }
    end
  end
end
