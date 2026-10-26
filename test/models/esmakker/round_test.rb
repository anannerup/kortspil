require "test_helper"

module Esmakker
  # Seam 1: what a seat of a dealt runde sees, who deals, and the runde
  # rebuilt from its stored form.
  class RoundTest < ActiveSupport::TestCase
    setup do
      @deal = Deal.shuffled(shuffler: Random.new(3))
      @round = Round.new(rules: Rules.standard, deal: @deal, dealer: 2)
    end

    test "a seat sees its own 13 cards and only how many the others and the kitty hold" do
      view = @round.view_for(1)

      assert_equal @deal.hand(1).map(&:to_s).sort, view[:hand].sort
      assert_equal({ 0 => 13, 2 => 13, 3 => 13 }, view[:card_counts])
      assert_equal 3, view[:kitty_count]
      hidden = (@deal.hands.values_at(0, 2, 3).flatten + @deal.kitty).map(&:to_s)
      assert_empty hidden & view.to_json.scan(/"([2-9TJQKA][CDHS]|X\d)"/).flatten, "no other seat's card and no kitty card"
    end

    test "the hand is shown by suit, colours alternating, ace high, jokers last" do
      hand = %w[X2 AH 2C KS TD X1 3C 9H JD QS 4S 5D 7H]
      deal = Deal.parse((hand + (Card.deck.map(&:to_s) - hand)).join(" "))

      shown = Round.new(rules: Rules.standard, deal:, dealer: 0).view_for(0)[:hand]

      assert_equal %w[2C 3C 5D TD JD 4S QS KS 7H 9H AH X1 X2], shown
    end

    test "the forhånd is the seat after the kortgiver, and the kortgiver moves clockwise" do
      assert_equal 2, @round.view_for(0)[:dealer]
      assert_equal 3, @round.view_for(0)[:forhand]
      assert_equal 3, @round.next_dealer

      last = Round.new(rules: Rules.standard, deal: @deal, dealer: 3)
      assert_equal 0, last.forhand
      assert_equal 0, last.next_dealer
      assert_equal [ 1, 2, 3, 0 ], (0..3).map { |dealer| Seats.forhand(dealer) }
    end

    test "the forhånd opens the meldingsrunde, offered every melding on the bord's ladder or pas" do
      view = @round.view_for(3)

      assert_equal :bidding, view[:phase]
      assert_equal [ 3, 3 ], [ view[:to_act], view[:bidding][:to_act] ]
      assert_equal [ 3 ], @round.seats_to_act
      assert_equal Ladder.standard.meldinger.map(&:to_s), view[:choices][:meldinger]
      assert view[:choices][:pas]
      assert_not view[:choices][:det_kan_jeg_selv]
      assert_equal({ meldinger: [], det_kan_jeg_selv: false, gaa_med: false, pas: false, jernhaand: false, trumps: [], aces: [], turn_card: false, accept_trump: false, bank: false, discard: false,
                     fordaekt: [] },
                   @round.view_for(0)[:choices])
      assert_equal :unknown_intent, @round.apply(3, Object.new).reason
      assert_equal :not_your_turn, @round.apply(0, Bidding::Pas.new).reason
      assert_not @round.complete?
    end

    test "the ladder follows the bord's påhæng order" do
      round = Round.new(rules: Rules.new(pahaeng_order: %w[halve vip gode]), deal: @deal, dealer: 2)

      assert_equal %w[8 8gode 8vip 8halve 9], round.view_for(3)[:choices][:meldinger].first(5)
    end

    test "each bidding intent is logged as one token, and the runde replays from the log" do
      round = apply(@round, [ 3, bid("9") ], [ 0, bid("10halve") ], [ 3, Bidding::DetKanJegSelv.new ], [ 0, Bidding::Pas.new ],
                    [ 1, bid("ren_sol") ], [ 3, Bidding::GaaMed.new ])

      assert_equal "3:9 0:10halve 3:selv 0:pas 1:ren_sol 3:med", round.actions_string
      assert_equal round, Round.from_strings(rules: Rules.standard, deal: round.deal_string, dealer: 2, actions: round.actions_string)
      assert_equal [ "ren_sol", 1 ], round.view_for(0)[:bidding].values_at(:melding, :holder)
    end

    test "a melder of a melding not played yet ends the runde: shown to all, not played, and the spil goes on" do
      round = apply(@round, [ 3, bid("9") ], [ 0, bid("sol") ], [ 3, Bidding::DetKanJegSelv.new ], [ 0, Bidding::Pas.new ],
                    [ 1, Bidding::Pas.new ], [ 2, Bidding::Pas.new ])

      assert_equal :complete, round.phase
      assert_empty round.seats_to_act
      assert_equal({ kind: :not_played, melder: 3, melding: "sol", trump: nil, called_ace: nil, esmakker: nil, selvmakker: false,
                     tricks_won: [], stik: 0, gik_hjem: false, vip_card: nil, banks: 0, points: [ 0, 0, 0, 0 ] }, round.result.to_h)
      (0..3).each do |seat|
        assert_equal({ kind: :melder, melder: 3, melding: "sol", went_with: [], reason: nil, dealer: nil }, round.view_for(seat)[:bidding][:outcome])
      end
      assert_not round.redeal?
      assert_equal 3, round.next_dealer
      assert_equal :bidding_complete, round.apply(0, Bidding::Pas.new).reason
    end

    test "all four pass: a redeal, which the former forhånd deals" do
      round = apply(@round, *[ 3, 0, 1, 2 ].map { |seat| [ seat, Bidding::Pas.new ] })

      assert_equal :redeal, round.phase
      assert round.redeal?
      assert_empty round.seats_to_act
      assert_equal 3, round.next_dealer
      assert_equal "all_passed", round.view_for(0)[:bidding][:outcome].as_json["reason"]
    end

    test "a jernhånd follows from the hand; only its holder may claim it, before the first bid, and the same kortgiver deals again" do
      round = Round.new(rules: Rules.standard, deal: jernhaand_deal(seat: 1), dealer: 2)

      assert_equal [ 1 ], round.jernhaand_seats
      assert round.view_for(1)[:choices][:jernhaand]
      assert_not round.view_for(0)[:choices][:jernhaand]
      assert_not round.view_for(0).to_json.include?("jernhaand_claimable"), "nobody learns who holds a jernhånd"
      assert_equal :no_jernhaand, round.apply(0, Bidding::ClaimJernhaand.new).reason

      claimed = apply(round, [ 3, Bidding::Pas.new ], [ 1, Bidding::ClaimJernhaand.new ])
      assert_equal [ :redeal, 2 ], [ claimed.phase, claimed.next_dealer ]
      assert_equal "3:pas 1:jernhaand", claimed.actions_string

      after_bid = apply(round, [ 3, bid("8") ])
      assert_equal :bidding_started, after_bid.apply(1, Bidding::ClaimJernhaand.new).reason
    end

    test "a runde is stored as its deal and its action log, and replays to the same state" do
      rebuilt = Round.from_strings(rules: Rules.standard, deal: @round.deal_string, dealer: 2, actions: @round.actions_string)

      assert_equal 55, @round.deal_string.split.size
      assert_equal "", @round.actions_string
      assert_equal @round, rebuilt
      (0..3).each { |seat| assert_equal @round.view_for(seat), rebuilt.view_for(seat) }
    end

    test "a seeded deal replays the same from storage every time" do
      stored = Deal.shuffled(shuffler: Random.new(11)).to_s

      first = Round.from_strings(rules: Rules.standard, deal: stored, dealer: 1)
      second = Round.from_strings(rules: Rules.standard, deal: Deal.shuffled(shuffler: Random.new(11)).to_s, dealer: 1)

      assert_equal first, second
    end

    test "a corrupt stored runde does not load" do
      assert_raises(ArgumentError) { Round.from_strings(rules: Rules.standard, deal: @round.deal_string, dealer: 4) }
      assert_raises(ArgumentError) { Round.from_strings(rules: Rules.standard, deal: @round.deal_string, dealer: 0, actions: "nonsense") }
      assert_raises(ArgumentError, "not the forhånd's turn") { Round.from_strings(rules: Rules.standard, deal: @round.deal_string, dealer: 0, actions: "2:pas") }
      assert_raises(ArgumentError) { Round.from_strings(rules: Rules.standard, deal: @round.deal_string, dealer: 0, actions: "1:7") }
    end

    test "the action log is seat:token entries" do
      actions = Action.parse_log("1:pas 2:9")

      assert_equal [ Action.new(seat: 1, token: "pas"), Action.new(seat: 2, token: "9") ], actions
      assert_equal "1:pas 2:9", Action.log_string(actions)
      assert_raises(ArgumentError) { Action.parse("5:pas") }
    end

    private

    def bid(code) = Bidding::Bid.new(melding: Melding.parse(code))

    def apply(round, *steps)
      steps.reduce(round) do |before, (seat, intent)|
        result = before.apply(seat, intent)
        assert result.accepted?, "seat #{seat} #{intent.inspect}: #{result.reason}"
        result.round
      end
    end

    # A deal where `seat` holds only number cards 2–10.
    def jernhaand_deal(seat:)
      numbers = Card.deck.reject(&:joker?).select { |card| %w[2 3 4 5 6 7 8 9 T].include?(card.rank) }.first(13)
      rest = Card.deck - numbers
      hands = (0..3).map { |other| other == seat ? numbers : rest.shift(13) }
      Deal.new(hands:, kitty: rest)
    end
  end
end
