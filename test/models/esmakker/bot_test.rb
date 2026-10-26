require "test_helper"

module Esmakker
  # The first es-makker bot (docs/bots/esmakker-strategy.md §2) through a
  # Round, reading only the seat's view: it melder 9 when it may, otherwise
  # pas; never goes with on sol, never says "det kan jeg selv", never
  # claims a jernhånd; never banks; and everything else is a legal choice
  # drawn at random, so a whole runde of every kind plays to its end on its
  # choices alone.
  #
  # Seat 0 deals, so seat 1 is forhånd.
  class BotTest < ActiveSupport::TestCase
    NINE = Bidding::Bid.new(melding: Melding.parse("9"))

    test "the forhånd melder 9; once 9 stands, the next seats say pas" do
      round = fresh_round

      assert_equal NINE, choose(round, 1)
      round = play(round, [ 1, NINE ])
      [ 2, 3, 0 ].each do |seat|
        assert_equal Bidding::Pas.new, choose(round, seat)
        round = play(round, [ seat, choose(round, seat) ])
      end
      assert_equal [ 1, "9" ], [ round.outcome.melder, round.outcome.melding.to_s ]
    end

    test "over an 8 it melder 9; over a higher melding it says pas" do
      assert_equal NINE, choose(play(fresh_round, [ 1, bid("8vip") ]), 2)
      assert_equal Bidding::Pas.new, choose(play(fresh_round, [ 1, bid("9gode") ]), 2)
    end

    test "it never goes with on a sol-melding" do
      round = play(fresh_round, [ 1, bid("sol") ])

      assert round.view_for(2)[:choices][:gaa_med]
      assert_equal Bidding::Pas.new, choose(round, 2)
    end

    test "it never says det kan jeg selv: served a 9, the holder says pas" do
      round = play(fresh_round, [ 1, bid("8") ], [ 2, NINE ])
      assert_equal 1, round.to_act
      assert round.view_for(1)[:choices][:det_kan_jeg_selv]

      assert_equal Bidding::Pas.new, choose(round, 1)
    end

    test "it never claims a jernhånd" do
      jern = %w[2C 3C 4C 5C 6C 7C 8C 9C TC 2D 3D 4D 5D]
      round = Round.new(rules: Rules.standard, deal: deal_with(hands: { 2 => jern }, kitty: %w[QS KS AS]), dealer: 0)
      assert round.view_for(2)[:choices][:jernhaand]

      assert_nil choose(round, 2), "not its turn, and it claims nothing"
      round = play(round, [ 1, Bidding::Pas.new ])
      assert_equal NINE, choose(round, 2)
    end

    test "it never banks: in vip's bank window no seat does anything" do
      round = play(fresh_round, [ 1, bid("8vip") ], [ 2, Bidding::Pas.new ], [ 3, Bidding::Pas.new ], [ 0, Bidding::Pas.new ])
      round = play(round, [ round.to_act, choose(round, round.to_act) ]) until round.banking?

      assert(Seats::ALL.any? { |seat| round.view_for(seat)[:choices][:bank] })
      Seats::ALL.each { |seat| assert_nil choose(round, seat), "seat #{seat}" }
    end

    test "a seat not to act does nothing" do
      round = fresh_round

      [ 0, 2, 3 ].each { |seat| assert_nil choose(round, seat) }
    end

    # Every kind of melding the bots might be served: a human (here, the
    # test) bids it and the others pass; then the bots make every choice
    # (trump, the ace, turning at vip, the kitty, fordækt, the cards; at
    # halve the esmakker's trump) and the runde plays to its end, every
    # choice accepted. At vip the bank window runs out unbanked.
    %w[8 9 9gode 8halve 8vip sol ren_sol bordlaegger ren_bordlaegger].each do |melding|
      test "every choice it makes after #{melding} is legal, and the runde plays to its end" do
        5.times do |seed|
          round = Round.new(rules: Rules.standard, deal: Deal.shuffled(shuffler: Random.new(seed)), dealer: 0)
          round = play(round, [ 1, bid(melding) ], [ 2, Bidding::Pas.new ], [ 3, Bidding::Pas.new ], [ 0, Bidding::Pas.new ])
          random = Random.new(seed)
          200.times do
            break if round.complete?

            if round.banking?
              Seats::ALL.each { |seat| assert_nil choose(round, seat, random:) }
              round = play(round, [ round.play.melder, CloseBankWindow.new ])
            else
              seat = round.to_act
              round = play(round, [ seat, choose(round, seat, random:) ])
            end
          end
          assert round.complete?, "seed #{seed}: the runde did not end"
        end
      end
    end

    test "the same lots make the same choices" do
      round = play(fresh_round, [ 1, NINE ], [ 2, Bidding::Pas.new ], [ 3, Bidding::Pas.new ], [ 0, Bidding::Pas.new ])

      assert_equal choose(round, 1, random: Random.new(7)), choose(round, 1, random: Random.new(7))
    end

    private

    def fresh_round = Round.new(rules: Rules.standard, deal: Deal.shuffled(shuffler: Random.new(1)), dealer: 0)

    def choose(round, seat, random: Random.new(0)) = Bot.new(random:).choose(round.view_for(seat))

    def bid(code) = Bidding::Bid.new(melding: Melding.parse(code))

    # A deal with the given cards in the given hands (and kitty); the rest
    # of the deck fills the other places in order.
    def deal_with(hands:, kitty:)
      placed = (hands.values.flatten + kitty).map { |code| Card.parse(code) }
      rest = Card.deck - placed
      filled = (0..3).map do |seat|
        own = hands.fetch(seat, []).map { |code| Card.parse(code) }
        own + rest.shift(Deal::HAND_SIZE - own.size)
      end
      Deal.new(hands: filled, kitty: kitty.map { |code| Card.parse(code) })
    end

    def play(round, *steps)
      steps.reduce(round) do |before, (seat, intent)|
        assert intent, "seat #{seat} chose nothing at #{before.phase}"
        result = before.apply(seat, intent)
        assert result.accepted?, "seat #{seat} #{intent.inspect}: #{result.reason}"
        result.round
      end
    end
  end
end
