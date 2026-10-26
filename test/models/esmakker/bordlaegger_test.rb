require "test_helper"

module Esmakker
  # Seam 1 for ticket 10: bordlægger and ren bordlægger through a Round
  # (REGLER §2.0 "Sol, ren sol og bordlægger"): played as sol and ren sol,
  # except that the melder's cards lie open for everyone once the first
  # stik is taken; only the melder's, not those who went with. Settled with
  # the bord's own amounts, and replayed from the log.
  #
  # Seat 0 deals, so seat 1 is forhånd.
  class BordlaeggerTest < ActiveSupport::TestCase
    PAS = Bidding::Pas.new
    MED = Bidding::GaaMed.new

    test "the melder's hand is hidden until the first stik is taken, then open in every seat's view, each card leaving it as she plays it" do
      hands = { 1 => %w[2S 3H 4H], 2 => %w[KS], 3 => %w[QS], 0 => %w[JS] }
      round = bordlaegger_round(hands:, kitty: %w[5H 6H 7H])
      assert_equal [ :exchanging, [ 1 ] ], [ round.phase, round.play.players ]
      assert_hidden(round, melder: 1, cards: %w[3H 4H])

      round = kept(round)
      round = play(round, [ 1, card("2S") ], [ 2, card("KS") ], [ 3, card("QS") ])
      assert_equal :playing, round.phase
      assert_hidden(round, melder: 1, cards: %w[3H 4H])

      round = play(round, [ 0, card("JS") ])
      melder_hand = round.view_for(1)[:hand]
      assert_equal 12, melder_hand.size
      (0..3).each do |seat|
        assert_equal({ seat: 1, cards: melder_hand }, round.view_for(seat)[:play][:open_hand], "seat #{seat} sees the melder's hand after stik 1")
      end

      # Seat 2 took stik 1 and leads; the melder's card leaves the open hand as she plays it.
      [ 2, 3, 0 ].each { |seat| round = play(round, [ seat, round.default_intent(seat) ]) }
      played = round.default_intent(1).card.to_s
      round = play(round, [ 1, round.default_intent(1) ])
      (0..3).each do |seat|
        open_hand = round.view_for(seat)[:play][:open_hand]
        assert_equal [ 11, false ], [ open_hand[:cards].size, open_hand[:cards].include?(played) ]
        assert_equal round.view_for(1)[:hand], open_hand[:cards]
      end
    end

    test "only the melder's hand is laid open: those who went with keep theirs hidden" do
      round = bordlaegger_round(deal: Deal.shuffled(shuffler: Random.new(7)), bids: [ [ 1, bid("bordlaegger") ], [ 2, MED ], [ 3, PAS ], [ 0, PAS ] ])
      round = play_stik(kept(round), 1)

      assert_equal [ 1, 2 ], round.play.players
      went_with = round.view_for(2)[:hand]
      [ 0, 3 ].each do |seat|
        view = round.view_for(seat)
        assert_equal 1, view[:play][:open_hand][:seat]
        went_with.each { |code| assert_not view.to_json.include?("\"#{code}\""), "seat #{seat} never sees #{code} in the hand of one who went with" }
      end
    end

    test "sol and ren sol lay nothing open" do
      %w[sol ren_sol].each do |melding|
        round = play_stik(kept(bordlaegger_round(deal: Deal.shuffled(shuffler: Random.new(3)), melding:)), 1)
        (0..3).each { |seat| assert_nil round.view_for(seat)[:play][:open_hand], "#{melding}, seat #{seat}" }
      end
    end

    test "bordlægger may take one stik; ren bordlægger none: one stik and she is væltet, the runde stops and she pays each modspiller 6" do
      round = kept(bordlaegger_round(hands: { 1 => %w[KS], 2 => %w[2S], 3 => %w[3S], 0 => %w[4S] }, kitty: %w[2H 3H 4H]))
      round = play(round, [ 1, card("KS") ], [ 2, card("2S") ], [ 3, card("3S") ], [ 0, card("4S") ])
      assert_equal [ :playing, [], 1 ], [ round.phase, round.play.vaeltet, round.view_for(0)[:play][:most_stik] ], "bordlægger may take one"

      round = kept(bordlaegger_round(hands: { 1 => %w[KS], 2 => %w[2S], 3 => %w[3S], 0 => %w[4S] }, kitty: %w[2H 3H 4H], melding: "ren_bordlaegger"))
      assert_equal 0, round.view_for(0)[:play][:most_stik]
      round = play(round, [ 1, card("KS") ], [ 2, card("2S") ], [ 3, card("3S") ], [ 0, card("4S") ])

      assert_equal [ :complete, :sol, [ 1 ], [ 6, -18, 6, 6 ] ], [ round.phase, round.result.kind, round.result.vaeltet, round.result.points ]
      assert_equal "ren_bordlaegger", round.view_for(2)[:result][:melding]
    end

    test "settled with the bord's values: bordlægger and ren bordlægger each their own amount" do
      rules = Rules.from_h(points: { bordlaegger: 7, ren_bordlaegger: 9.5 })
      values = rules.points
      klaret = SolResult.settled(melder: 1, melding: Melding.bordlaegger, players: [ 1 ], most_stik: 1, vaeltet: [], tricks_won: [ 4, 1, 4, 4 ], values:)
      two = SolResult.settled(melder: 1, melding: Melding.bordlaegger, players: [ 1, 3 ], most_stik: 1, vaeltet: [ 3 ], tricks_won: [ 5, 1, 5, 2 ], values:)
      assert_equal [ -7, 21, -7, -7 ], klaret.points
      assert_equal [ 0, 14, 0, -14 ], two.points

      round = kept(bordlaegger_round(hands: { 1 => %w[KS], 2 => %w[2S], 3 => %w[3S], 0 => %w[4S] }, kitty: %w[2H 3H 4H], melding: "ren_bordlaegger", rules:))
      round = play(round, [ 1, card("KS") ], [ 2, card("2S") ], [ 3, card("3S") ], [ 0, card("4S") ])
      assert_equal [ 9.5, -28.5, 9.5, 9.5 ], round.result.points
    end

    test "random bordlægger runder: the open hand at every step, zero sum, and the log replays to the same runde" do
      30.times do |seed|
        random = Random.new(seed)
        melding = %w[bordlaegger ren_bordlaegger][seed % 2]
        went_with = [ 2, 3, 0 ].select { random.rand < 0.4 }
        bids = [ [ 1, bid(melding) ], *[ 2, 3, 0 ].map { |seat| [ seat, went_with.include?(seat) ? MED : PAS ] } ]
        round = bordlaegger_round(deal: Deal.shuffled(shuffler: random), bids:)
        until round.complete?
          round = play(round, [ round.to_act, random_step(round, random) ])
          expected = round.play.tricks.empty? ? nil : { seat: 1, cards: round.play.open_hand[:cards] }
          if expected
            (0..3).each { |seat| assert_equal expected, round.view_for(seat)[:play][:open_hand], "seed #{seed}, seat #{seat}" }
            assert_equal round.view_for(1)[:hand], expected[:cards]
          else
            (0..3).each { |seat| assert_nil round.view_for(seat)[:play][:open_hand], "seed #{seed}, seat #{seat}" }
          end
        end

        assert_equal 0, round.result.points.sum, "seed #{seed}"
        assert_equal round, Round.from_strings(rules: Rules.standard, deal: round.deal_string, dealer: 0, actions: round.actions_string)
      end
    end

    private

    def bid(code) = Bidding::Bid.new(melding: Melding.parse(code))
    def card(code) = PlayCard.new(card: Card.parse(code))
    def discard(*codes) = Discard.new(cards: codes.map { |code| Card.parse(code) })

    # No seat but the melder sees her cards, and nobody sees them laid open.
    def assert_hidden(round, melder:, cards:)
      (0..3).each { |seat| assert_nil round.view_for(seat)[:play][:open_hand], "seat #{seat}: hidden before stik 1" }
      (Seats::ALL - [ melder ]).each do |seat|
        cards.each { |code| assert_not round.view_for(seat).to_json.include?("\"#{code}\""), "seat #{seat} sees #{code} before stik 1" }
      end
    end

    def deal_with(hands:, kitty: nil)
      placed = (hands.values.flatten + kitty.to_a).map { |code| Card.parse(code) }
      rest = Card.deck - placed
      filled = (0..3).map do |seat|
        own = hands.fetch(seat, []).map { |code| Card.parse(code) }
        own + rest.shift(Deal::HAND_SIZE - own.size)
      end
      kitty_cards = kitty ? kitty.map { |code| Card.parse(code) } : rest.shift(Deal::KITTY_SIZE)
      Deal.new(hands: filled, kitty: kitty_cards)
    end

    # Seat 1 (forhånd) bids the melding and the others pass, unless `bids`
    # says otherwise.
    def bordlaegger_round(hands: {}, kitty: nil, melding: "bordlaegger", bids: nil, deal: nil, rules: Rules.standard)
      round = Round.new(rules:, deal: deal || deal_with(hands:, kitty:), dealer: 0)
      play(round, *(bids || [ [ 1, bid(melding) ], [ 2, PAS ], [ 3, PAS ], [ 0, PAS ] ]))
    end

    # Everyone lays the kitty back: nobody exchanges.
    def kept(round)
      round = play(round, [ round.to_act, round.default_intent(round.to_act) ]) while round.phase == :exchanging
      round
    end

    # Plays `count` whole stik with each seat's first legal card.
    def play_stik(round, count)
      (count * SEAT_COUNT).times { round = play(round, [ round.to_act, round.default_intent(round.to_act) ]) }
      round
    end

    # A random exchange (any cards of the hand, as many as the kitty holds)
    # or a random legal card.
    def random_step(round, random)
      seat = round.to_act
      return card(round.view_for(seat)[:play][:legal_moves].sample(random:)) unless round.phase == :exchanging

      size = round.view_for(seat)[:play][:discard_size]
      discard(*round.view_for(seat)[:hand].sample(size, random:))
    end

    def play(round, *steps)
      steps.reduce(round) do |before, (seat, intent)|
        result = before.apply(seat, intent)
        assert result.accepted?, "seat #{seat} #{intent.inspect}: #{result.reason}"
        result.round
      end
    end
  end
end
