require "test_helper"

module Esmakker
  # Seam 1 for ticket 09: sol and ren sol through a Round (REGLER §2.0 "Sol,
  # ren sol og bordlægger", "Bytning med katten"): the kitty in turn (the
  # melder, those who went with, then clockwise from the melder), the
  # forhånd leads, no trump, the ace lowest, a led joker wins, væltet, the
  # runde played to the end and stopped once every sol player is væltet,
  # the settlement per sol player, and the replay from the log.
  #
  # Seat 0 deals, so seat 1 is forhånd.
  class SolPlayTest < ActiveSupport::TestCase
    PAS = Bidding::Pas.new
    MED = Bidding::GaaMed.new

    test "sol: no trump, no ace, no makker; the melder takes the kitty first and sees it alone" do
      round = sol_round(kitty: %w[X1 X2 X3])

      assert_equal [ :exchanging, 1 ], [ round.phase, round.to_act ]
      melder = round.view_for(1)
      assert_equal [ 16, %w[X1 X2 X3], true, [], [] ], [ melder[:hand].size, melder[:play][:kitty_cards], melder[:choices][:discard], melder[:choices][:trumps], melder[:choices][:aces] ]
      assert_equal({ kind: :sol, players: [ 1 ], most_stik: 1, vaeltet: [], exchange_order: [ 1, 2, 3, 0 ], exchanging: 1, discard_size: 3 },
                   melder[:play].slice(:kind, :players, :most_stik, :vaeltet, :exchange_order, :exchanging, :discard_size))
      assert_equal [ nil, nil, nil ], melder[:play].values_at(:trump, :called_ace, :esmakker)
      [ 0, 2, 3 ].each do |seat|
        view = round.view_for(seat)
        assert_equal [ [], false, 16 ], [ view[:play][:kitty_cards], view[:choices][:discard], view[:card_counts][1] ]
        assert_not view.to_json.match?(/"X\d"/), "seat #{seat} never sees the kitty"
      end
      assert_equal :not_now, round.apply(1, ChooseTrump.new(trump: Trump.parse("H"))).reason
      assert_equal :not_now, round.apply(1, CallAce.new(suit: "H")).reason
      assert_equal :not_your_turn, round.apply(2, discard("X1", "X2", "X3")).reason
      assert_equal :wrong_card_count, round.apply(1, discard("X1", "X2")).reason
    end

    test "the kitty goes round: the melder, those who went with in their order, then clockwise from the melder; each exchanges what is left" do
      # Seat 1 bids 9, seat 2 sol, seat 1 goes with: seat 2 is melder, seat 1 went with.
      round = sol_round(kitty: %w[X1 X2 X3], bids: [ [ 1, bid("9") ], [ 2, bid("sol") ], [ 1, MED ], [ 3, PAS ], [ 0, PAS ] ])
      assert_equal [ [ 2, 1 ], [ 2, 1, 3, 0 ] ], [ round.play.players, round.play.exchange_order ]

      # The melder takes one, lays one of her own away and the other two back.
      round = play(round, [ 2, discard("2H", "X2", "X3") ])
      assert_equal [ :exchanging, 1, 13 ], [ round.phase, round.to_act, round.view_for(2)[:hand].size ]
      assert_includes round.view_for(2)[:hand], "X1"
      assert_equal %w[2H], round.view_for(2)[:play][:discarded]
      went_with = round.view_for(1)
      assert_equal [ 15, %w[X2 X3], 2 ], [ went_with[:hand].size, went_with[:play][:kitty_cards], went_with[:play][:discard_size] ]
      [ 0, 1, 3 ].each { |seat| assert_not round.view_for(seat).to_json.include?("\"2H\""), "seat #{seat} never sees what the melder laid away" }

      # The one who went with keeps her hand; the rest go on clockwise from the melder.
      round = play(round, [ 1, discard("X2", "X3") ])
      assert_equal [ 3, %w[X2 X3] ], [ round.to_act, round.view_for(3)[:play][:kitty_cards] ]
      round = play(round, [ 3, discard("2S", "X3") ])
      assert_equal [ 0, %w[X3] ], [ round.to_act, round.view_for(0)[:play][:kitty_cards] ]
      round = play(round, [ 0, discard("2C") ])

      assert_equal [ :playing, 1 ], [ round.phase, round.to_act ], "the kitty is empty; the forhånd leads, not the melder"
      assert_equal [ [], [ 13 ] * 4 ], [ round.view_for(2)[:play][:kitty_cards], (0..3).map { |seat| round.view_for(seat)[:hand].size } ]
      assert_includes round.view_for(3)[:hand], "X2"
      assert_includes round.view_for(0)[:hand], "X3"
    end

    test "when nobody takes the kitty, every seat has its turn and the kitty is out of the runde" do
      round = sol_round(kitty: %w[X1 X2 X3])
      round = play(round, *[ 1, 2, 3, 0 ].map { |seat| [ seat, discard("X1", "X2", "X3") ] })

      assert_equal [ :playing, 1 ], [ round.phase, round.to_act ]
      (0..3).each { |seat| assert_not round.view_for(seat).to_json.match?(/"X\d"/) }
    end

    test "the ace is the lowest card: the hand is sorted with the ace first, and an ace never takes a stik" do
      hands = { 1 => %w[3S], 2 => %w[AS 5S KS], 3 => %w[2S], 0 => %w[4S] }
      spades = ->(round) { round.view_for(2)[:hand].select { |code| code.end_with?("S") } }
      before = Round.new(rules: Rules.standard, deal: deal_with(hands:, kitty: %w[2H 3H 4H]), dealer: 0)
      assert_equal %w[5S KS AS], spades.(before), "the ace highest before the sol-melding"

      round = kept(sol_round(hands:, kitty: %w[2H 3H 4H]))
      assert_equal %w[AS 5S KS], spades.(round), "the ace lowest in the hand's order"

      round = play(round, [ 1, card("3S") ], [ 2, card("AS") ], [ 3, card("2S") ], [ 0, card("4S") ])
      assert_equal [ 0, [ 1, 0, 0, 0 ] ], [ round.play.trick.leader, round.view_for(0)[:play][:tricks_won] ]
    end

    test "a led joker wins the stik; a joker not led is worth nothing; there is no trump" do
      hands = { 1 => %w[X1 3S], 2 => %w[KS X2], 3 => %w[2S 4H], 0 => %w[4S AH] }
      round = kept(sol_round(hands:, kitty: %w[2H 3H 5H]))

      round = play(round, [ 1, card("X1") ], [ 2, card("KS") ], [ 3, card("2S") ], [ 0, card("4S") ])
      assert_equal 1, round.play.trick.leader, "the led joker took it"
      round = play(round, [ 1, card("3S") ], [ 2, card("X2") ], [ 3, card("5S") ], [ 0, card("AH") ])
      assert_equal [ 3, [ 0, 1, 0, 1 ] ], [ round.play.trick.leader, round.play.tricks_won ], "the joker not led and the off-suit card are worth nothing"
    end

    test "a sol player who takes one stik too many is væltet; the runde goes on; it stops once every sol player is væltet" do
      hands = { 1 => %w[KS QS 2H], 2 => %w[KH QH 2S 3S], 3 => %w[3H 4H 4S 5S], 0 => %w[5H 6H 6S 7S] }
      round = kept(sol_round(hands:, kitty: %w[7H 8H 9H], bids: [ [ 1, bid("sol") ], [ 2, MED ], [ 3, PAS ], [ 0, PAS ] ]))
      assert_equal [ 1, 2 ], round.play.players

      round = play(round, [ 1, card("KS") ], [ 2, card("2S") ], [ 3, card("4S") ], [ 0, card("6S") ])
      assert_empty round.view_for(0)[:play][:vaeltet], "sol may take one stik"
      round = play(round, [ 1, card("QS") ], [ 2, card("3S") ], [ 3, card("5S") ], [ 0, card("7S") ])
      assert_equal [ [ 1 ], :playing ], [ round.view_for(3)[:play][:vaeltet], round.phase ], "væltet, but another sol player still plays"

      round = play(round, [ 1, card("2H") ], [ 2, card("KH") ], [ 3, card("3H") ], [ 0, card("5H") ])
      round = play(round, [ 2, card("QH") ], [ 3, card("4H") ], [ 0, card("6H") ])
      round = play(round, [ 1, round.default_intent(1) ])

      assert_equal :complete, round.phase, "every sol player is væltet after 4 stik"
      result = round.result
      assert_equal [ :sol, [ 1, 2 ], [ 1, 2 ], [ 6, -6, -6, 6 ] ], [ result.kind, result.players, result.vaeltet, result.points ]
      assert_equal({ players: [ 1, 2 ], most_stik: 1, vaeltet: [ 1, 2 ] }, round.view_for(0)[:result][:sol])
    end

    test "ren sol: one stik and she is væltet; alone, the runde stops there and she pays each modspiller" do
      round = kept(sol_round(hands: { 1 => %w[KS], 2 => %w[2S], 3 => %w[3S], 0 => %w[4S] }, kitty: %w[2H 3H 4H], melding: "ren_sol"))
      assert_equal 0, round.view_for(0)[:play][:most_stik]

      round = play(round, [ 1, card("KS") ], [ 2, card("2S") ], [ 3, card("3S") ], [ 0, card("4S") ])
      assert_equal [ :complete, [ 4, -12, 4, 4 ] ], [ round.phase, round.result.points ]
    end

    test "a sol player who keeps within her stik wins the amount from each modspiller; the runde is played to the end" do
      seed = (0..500).find do |candidate|
        round = play_out(sol_round(deal: Deal.shuffled(shuffler: Random.new(candidate))))
        round.result.vaeltet.empty? && round.play.tricks.size == Play::STIK_COUNT
      end
      round = play_out(sol_round(deal: Deal.shuffled(shuffler: Random.new(seed))))

      assert_equal [ 13, [ -3, 9, -3, -3 ] ], [ round.play.tricks.size, round.result.points ]
    end

    test "random sol runder: zero sum, the væltet pay, and the log replays to the same runde" do
      40.times do |seed|
        random = Random.new(seed)
        melding = %w[sol ren_sol][seed % 2]
        went_with = [ 2, 3, 0 ].select { random.rand < 0.4 }
        bids = [ [ 1, bid(melding) ], *[ 2, 3, 0 ].map { |seat| [ seat, went_with.include?(seat) ? MED : PAS ] } ]
        round = sol_round(deal: Deal.shuffled(shuffler: random), melding:, bids:)
        round = play(round, [ round.to_act, random_step(round, random) ]) until round.complete?

        result = round.result
        assert_equal 0, result.points.sum, "seed #{seed}"
        result.vaeltet.each { |seat| assert_operator result.points[seat], :<, 0 } unless result.players.size == 4
        assert_equal round, Round.from_strings(rules: Rules.standard, deal: round.deal_string, dealer: 0, actions: round.actions_string)
      end
    end

    private

    def bid(code) = Bidding::Bid.new(melding: Melding.parse(code))
    def card(code) = PlayCard.new(card: Card.parse(code))
    def discard(*codes) = Discard.new(cards: codes.map { |code| Card.parse(code) })

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

    # Seat 1 (forhånd) bids the sol-melding and the others pass, unless
    # `bids` says otherwise.
    def sol_round(hands: {}, kitty: nil, melding: "sol", bids: nil, deal: nil)
      round = Round.new(rules: Rules.standard, deal: deal || deal_with(hands:, kitty:), dealer: 0)
      play(round, *(bids || [ [ 1, bid(melding) ], [ 2, PAS ], [ 3, PAS ], [ 0, PAS ] ]))
    end

    # Everyone lays the kitty back: nobody exchanges.
    def kept(round)
      round = play(round, [ round.to_act, round.default_intent(round.to_act) ]) while round.phase == :exchanging
      round
    end

    def play_out(round)
      round = play(round, [ round.to_act, round.default_intent(round.to_act) ]) until round.complete?
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
