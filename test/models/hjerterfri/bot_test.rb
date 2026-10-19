require "test_helper"

module Hjerterfri
  class BotTest < ActiveSupport::TestCase
    setup { @bot = Bot.new }

    # Following suit

    test "following suit, plays the highest card that still loses the stik" do
      view = view(legal: %w[3D 8D JD AD], trick: %w[TD 2D])

      assert_equal "8D", @bot.choose_play(view)
    end

    test "following suit with only winning cards, an early seat plays its lowest" do
      view = view(legal: %w[JD QD AD], trick: %w[TD])

      assert_equal "JD", @bot.choose_play(view)
    end

    test "following suit as the last seat with only winning cards, wins with the highest" do
      view = view(legal: %w[JD QD AD], trick: %w[TD 2D 3D])

      assert_equal "AD", @bot.choose_play(view)
    end

    test "dumps Q♠ under a higher spade" do
      view = view(legal: %w[3S QS], trick: %w[KS])

      assert_equal "QS", @bot.choose_play(view)
    end

    test "does not win with Q♠ while another spade will do" do
      assert_equal "AS", @bot.choose_play(view(legal: %w[QS AS], trick: %w[TS 2S 3S]))
      assert_equal "AS", @bot.choose_play(view(legal: %w[QS AS], trick: %w[TS]))
    end

    # Void in the led suit

    test "when void, dumps Q♠ first" do
      view = view(legal: %w[2C QS AH KD], trick: %w[5D])

      assert_equal "QS", @bot.choose_play(view)
    end

    test "when void without Q♠, dumps the highest heart" do
      view = view(legal: %w[AC 4H JH KS], trick: %w[5D])

      assert_equal "JH", @bot.choose_play(view)
    end

    test "when void without Q♠ or hearts, dumps the highest card" do
      view = view(legal: %w[4C TC 9S KD], trick: %w[5H])

      assert_equal "KD", @bot.choose_play(view)
    end

    # Leading

    test "leads the lowest card, avoiding hearts" do
      view = view(legal: %w[7C 5D 2H 9S], trick: [])

      assert_equal "5D", @bot.choose_play(view)
    end

    test "does not lead Q♠ or the spades above it while another card will do" do
      view = view(legal: %w[QS KS AS 9D], trick: [])

      assert_equal "9D", @bot.choose_play(view)
    end

    test "leads hearts only when nothing else is legal" do
      assert_equal "3H", @bot.choose_play(view(legal: %w[3H 9H], trick: []))
    end

    test "plays the only legal move" do
      assert_equal "2C", @bot.choose_play(view(legal: %w[2C], trick: []))
    end

    # Passing

    test "passes Q♠, then the highest hearts" do
      hand = %w[2C 3C 4C 5D 6D QS 2S 3H 9H JH 7D 8D 9D]

      assert_equal %w[QS JH 9H], @bot.choose_pass(hand)
    end

    test "keeps Q♠ when guarded by four lower spades" do
      hand = %w[2C 3C 4C 5D 6D QS 2S 3S 4S 5S 9H JH 7D]

      assert_equal %w[JH 9H 7D], @bot.choose_pass(hand)
    end

    test "passes A♠ and K♠ when it does not hold Q♠" do
      hand = %w[2C 3C 4C 5D 6D KS AS 3S 3H 9H JH 7D 8D]

      assert_equal %w[AS KS JH], @bot.choose_pass(hand)
    end

    test "keeps A♠ and K♠ when it holds Q♠, passing it instead" do
      hand = %w[2C 3C 4C 5D 6D KS AS QS 3H 9H 2H 7D 8D]

      assert_equal %w[QS 9H 3H], @bot.choose_pass(hand)
    end

    test "without danger cards, passes the highest cards" do
      hand = %w[2C 3C AC 5D 6D 2S 3S 4S 7C 9C KD 7D 8D]

      assert_equal %w[AC KD 9C], @bot.choose_pass(hand)
    end

    # Delay

    test "the delay is between 0.8 and 1.2 seconds and follows the injected random" do
      delays = 50.times.map { |seed| @bot.delay(random: Random.new(seed)) }

      assert delays.all? { |delay| delay.between?(0.8, 1.2) }
      assert_equal @bot.delay(random: Random.new(7)), @bot.delay(random: Random.new(7))
    end

    # Whole runden

    test "four bots play many seeded deals without an illegal move" do
      200.times do |seed|
        round = Round.new(rules: Rules.standard, deal: Deal.shuffled(shuffler: Random.new(seed)))

        until round.complete?
          seat = round.to_act
          card = @bot.choose_play(round.view_for(seat))
          result = round.apply(seat, Play.new(card:))
          assert result.accepted?, "seed #{seed}: seat #{seat} played #{card}: #{result.reason}"
          round = result.round
        end

        assert_includes [ 26, 78 ], round.points.sum, "seed #{seed}: every point is taken (78 after a moon)"
      end
    end

    test "passes three distinct cards from the hand of any seeded deal" do
      100.times do |seed|
        Deal.shuffled(shuffler: Random.new(seed)).hands.each do |hand|
          codes = hand.map(&:to_s)
          pass = @bot.choose_pass(codes)

          assert_equal 3, pass.uniq.size
          assert_empty pass - codes
        end
      end
    end

    private

    # A view as Round#view_for shows it, with only what the bot reads.
    def view(legal:, trick:)
      { legal_moves: legal, current_trick: trick.each_with_index.map { |card, seat| { seat:, card: } } }
    end
  end
end
