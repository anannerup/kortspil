require "test_helper"

module Esmakker
  # Seam 1 for ticket 07: vip (REGLER §2.0 "Vip") through a Round — the
  # melder calls the ace first, then turns the kitty's cards one by one and
  # takes the first, second or third as trump (the third in any case); a
  # joker is trumfløs; the cards not turned stay hidden from everyone; the
  # card taken doubles ×2/×4/×8 (Scoring); and the replay from the log.
  #
  # Seat 0 deals, so seat 1 is forhånd; seat 1 bids and the others pass.
  class VipTest < ActiveSupport::TestCase
    KITTY = %w[5D QS 9H].freeze
    # The bank window's time runs out (ticket 08), and the melder takes the kitty up.
    CLOSE = [ 1, CloseBankWindow.new ].freeze

    test "vip: the melder calls the ace first; nothing is turned and nobody names trump before" do
      round = melder_round(hands: { 1 => %w[AH], 2 => %w[AD] })

      assert_equal [ :calling_ace, [ 1 ] ], [ round.phase, round.seats_to_act ]
      choices = round.view_for(1)[:choices]
      assert_equal [ %w[C D S], [], false, false ], choices.values_at(:aces, :trumps, :turn_card, :accept_trump)
      assert_equal :not_now, round.apply(1, TurnCard.new).reason
      assert_equal :not_now, round.apply(1, AcceptTrump.new).reason
      assert_equal :not_now, round.apply(1, ChooseTrump.new(trump: Trump.parse("S"))).reason
      assert_equal :own_ace, round.apply(1, CallAce.new(suit: "H")).reason
      assert_equal :not_your_turn, round.apply(2, CallAce.new(suit: "D")).reason
    end

    test "after the ace the melder turns: one card at a time, face up for everyone, the rest hidden from all, herself included" do
      round = play(melder_round(hands: { 2 => %w[AD] }), [ 1, CallAce.new(suit: "D") ])

      assert_equal [ :turning, [ 1 ] ], [ round.phase, round.seats_to_act ]
      assert_equal [ true, false, [] ], round.view_for(1)[:choices].values_at(:turn_card, :accept_trump, :trumps)
      assert_equal :nothing_turned, round.apply(1, AcceptTrump.new).reason
      assert_equal :not_your_turn, round.apply(2, TurnCard.new).reason
      (0..3).each do |seat|
        view = round.view_for(seat)
        assert_equal [ [], nil, nil ], view[:play].values_at(:turned, :vip_card, :trump)
        assert_nil view[:play][:esmakker] unless seat == 2
        assert_hidden KITTY, view, "seat #{seat} before the turn"
      end

      first = play(round, [ 1, TurnCard.new ])
      assert_equal [ :turning, [ 1 ] ], [ first.phase, first.seats_to_act ]
      assert_equal [ true, true ], first.view_for(1)[:choices].values_at(:turn_card, :accept_trump)
      assert_equal [ false, false ], first.view_for(2)[:choices].values_at(:turn_card, :accept_trump)
      (0..3).each do |seat|
        view = first.view_for(seat)
        assert_equal [ %w[5D], nil, 3 ], [ view[:play][:turned], view[:play][:trump], view[:kitty_count] ]
        assert_hidden %w[QS 9H], view, "seat #{seat} after one card"
      end

      second = play(first, [ 1, TurnCard.new ])
      (0..3).each do |seat|
        assert_equal %w[5D QS], second.view_for(seat)[:play][:turned]
        assert_hidden %w[9H], second.view_for(seat), "seat #{seat} after two cards"
      end
    end

    test "she takes the first card: its suit is trump, ×2, the rest of the kitty stays hidden until she takes it up, and others never see it" do
      round = play(melder_round(hands: { 2 => %w[AD] }), [ 1, CallAce.new(suit: "D") ], [ 1, TurnCard.new ], [ 1, AcceptTrump.new ], CLOSE)

      assert_equal [ :discarding, [ 1 ], 16 ], [ round.phase, round.seats_to_act, round.view_for(1)[:hand].size ]
      (0..3).each do |seat|
        view = round.view_for(seat)
        assert_equal [ "D", 1, %w[5D] ], view[:play].values_at(:trump, :vip_card, :turned), "seat #{seat}: trump may be the called ace's suit"
        assert_equal 0, view[:kitty_count]
      end
      assert_equal %w[5D QS 9H].sort, round.view_for(1)[:play][:kitty_cards].sort, "she sees the whole kitty once she takes it up"
      [ 0, 2, 3 ].each { |seat| assert_hidden %w[QS 9H], round.view_for(seat), "seat #{seat} while she lays away" }

      laid = play(round, [ 1, discard("QS", "9H", round.view_for(1)[:hand].first) ])
      done = play_out(laid)
      [ 0, 2, 3 ].each do |seat|
        played = done.play.tricks.flat_map(&:cards).map(&:to_s)
        assert_hidden %w[QS 9H] - played, done.view_for(seat), "seat #{seat} after the runde"
      end
      assert_equal [ :played, 1, "D" ], [ done.result.kind, done.result.vip_card, done.result.trump.to_s ]
      assert_points done.result, factor: 2
    end

    test "she takes the second card: ×4" do
      round = play(melder_round(hands: { 2 => %w[AD] }), [ 1, CallAce.new(suit: "D") ], [ 1, TurnCard.new ], [ 1, TurnCard.new ], [ 1, AcceptTrump.new ], CLOSE)

      assert_equal [ :discarding, "S", 2 ], [ round.phase, round.play.trump.to_s, round.play.vip_card ]
      done = play_out(play(round, [ 1, Discard.new(cards: round.deal.kitty) ]))
      assert_equal [ 2, "S" ], [ done.result.vip_card, done.result.trump.to_s ]
      assert_points done.result, factor: 4
    end

    test "the third card is trump in any case: turning it names trump, ×8" do
      round = play(melder_round(hands: { 2 => %w[AD] }), [ 1, CallAce.new(suit: "D") ], [ 1, TurnCard.new ], [ 1, TurnCard.new ])

      third = play(round, [ 1, TurnCard.new ], CLOSE)
      assert_equal [ :discarding, "H", 3 ], [ third.phase, third.play.trump.to_s, third.play.vip_card ]
      (0..3).each { |seat| assert_equal %w[5D QS 9H], third.view_for(seat)[:play][:turned] }
      assert_equal :not_now, third.apply(1, TurnCard.new).reason
      assert_equal :not_now, third.apply(1, AcceptTrump.new).reason

      done = play_out(play(third, [ 1, Discard.new(cards: third.deal.kitty) ]))
      assert_points done.result, factor: 8
    end

    test "a turned joker is trumfløs, which doubles on top of its card (05's D3)" do
      round = play(melder_round(hands: { 2 => %w[AD] }, kitty: %w[X2 QS 9H]), [ 1, CallAce.new(suit: "D") ], [ 1, TurnCard.new ])
      assert_equal %w[X2], round.view_for(0)[:play][:turned]
      assert_equal [ true, true ], round.view_for(1)[:choices].values_at(:turn_card, :accept_trump), "she may go on past a joker"

      taken = play(round, [ 1, AcceptTrump.new ], CLOSE)
      assert_equal [ "trumfloes", 1 ], [ taken.view_for(3)[:play][:trump], taken.play.vip_card ]
      done = play_out(play(taken, [ 1, Discard.new(cards: taken.deal.kitty) ]))
      assert_points done.result, factor: 2 * 2

      third = play(melder_round(hands: { 2 => %w[AD] }, kitty: %w[5C QS X3]), [ 1, CallAce.new(suit: "D") ], *[ [ 1, TurnCard.new ] ] * 3, CLOSE)
      assert_equal [ "trumfloes", 3 ], [ third.play.trump.to_s, third.play.vip_card ]
      done = play_out(play(third, [ 1, Discard.new(cards: third.deal.kitty) ]))
      assert_points done.result, factor: 8 * 2
    end

    test "the esmakker stays hidden at vip; a called ace turned from the kitty tells everyone the melder is selvmakker" do
      hidden = play(melder_round(hands: { 3 => %w[AC] }), [ 1, CallAce.new(suit: "C") ], [ 1, TurnCard.new ], [ 1, AcceptTrump.new ])
      assert_equal 3, hidden.view_for(3)[:play][:esmakker]
      [ 0, 1, 2 ].each { |seat| assert_nil hidden.view_for(seat)[:play][:esmakker], "seat #{seat} does not know the esmakker" }

      round = play(melder_round(hands: { 1 => %w[2S] }, kitty: %w[5D AS 9H]), [ 1, CallAce.new(suit: "S") ], [ 1, TurnCard.new ])
      (0..3).each { |seat| assert_not round.view_for(seat)[:play][:selvmakker], "seat #{seat}: the ace is not turned yet" }
      turned = play(round, [ 1, TurnCard.new ])
      (0..3).each { |seat| assert_equal [ nil, true ], turned.view_for(seat)[:play].values_at(:esmakker, :selvmakker), "seat #{seat} saw the ace turned" }

      done = play_out(play(turned, [ 1, AcceptTrump.new ], CLOSE, [ 1, Discard.new(cards: turned.deal.kitty) ]))
      assert_equal [ true, [ 1 ], 2, "S" ], [ done.result.selvmakker, done.result.side, done.result.vip_card, done.result.trump.to_s ]
      assert_points done.result, factor: 4
    end

    test "a vip runde is stored as its log and replays to the same state and views" do
      round = play(melder_round(hands: { 3 => %w[AC] }), [ 1, CallAce.new(suit: "C") ], [ 1, TurnCard.new ], [ 1, TurnCard.new ], [ 1, AcceptTrump.new ], CLOSE)
      done = play_out(play(round, [ 1, Discard.new(cards: round.deal.kitty) ]))

      tokens = done.actions_string.split
      assert_equal %w[1:8vip 2:pas 3:pas 0:pas 1:esC 1:vend 1:vend 1:accepter 1:bankslut], tokens.first(9)
      assert tokens[9].start_with?("1:kast-")
      rebuilt = Round.from_strings(rules: Rules.standard, deal: done.deal_string, dealer: 0, actions: done.actions_string)
      assert_equal done, rebuilt
      assert_equal done.result, rebuilt.result
      (0..3).each { |seat| assert_equal done.view_for(seat), rebuilt.view_for(seat) }
      assert_raises(ArgumentError) do
        Round.from_strings(rules: Rules.standard, deal: done.deal_string, dealer: 0, actions: "1:8vip 2:pas 3:pas 0:pas 1:esC 1:accepter")
      end
      assert_raises(ArgumentError) do
        Round.from_strings(rules: Rules.standard, deal: done.deal_string, dealer: 0, actions: "1:8vip 2:pas 3:pas 0:pas 1:vend")
      end
    end

    test "seeded vip runder played through by the default choices replay from storage" do
      5.times do |seed|
        round = Round.new(rules: Rules.standard, deal: Deal.shuffled(shuffler: Random.new(seed)), dealer: 0)
        done = play_out(play(round, [ 1, bid("9vip") ], [ 2, Bidding::Pas.new ], [ 3, Bidding::Pas.new ], [ 0, Bidding::Pas.new ]))

        assert done.complete?
        assert_equal 1, done.result.vip_card, "the default takes the first card"
        assert_equal 0, done.result.points.sum
        assert_equal done, Round.from_strings(rules: Rules.standard, deal: done.deal_string, dealer: 0, actions: done.actions_string)
      end
    end

    private

    def bid(code) = Bidding::Bid.new(melding: Melding.parse(code))
    def discard(*codes) = Discard.new(cards: codes.map { |code| Card.parse(code) })

    # None of the cards appears anywhere in the view.
    def assert_hidden(cards, view, message)
      assert_empty cards & view.to_json.scan(/"([2-9TJQKA][CDHS]|X\d)"/).flatten, message
    end

    # The result's points: 8 is 1, (1 + overstik) or 1 × missing stik,
    # times `factor`; two against two each seat once, a selvmakker with each
    # of the three others.
    def assert_points(result, factor:)
      over = result.stik - result.melding.number
      per_pair = (over.negative? ? -over : 1 + over) * factor
      sign = result.gik_hjem? ? 1 : -1
      expected = (0..3).map do |seat|
        mine = result.side.include?(seat) ? sign : -sign
        mine * per_pair * (result.selvmakker && seat == result.melder ? 3 : 1)
      end
      assert_equal expected, result.points
    end

    # A deal with the given cards in the given hands (and kitty, by default
    # 5D QS 9H); the rest of the deck fills the other places in order.
    def deal_with(hands:, kitty: KITTY)
      placed = (hands.values.flatten + kitty).map { |code| Card.parse(code) }
      rest = Card.deck - placed
      filled = (0..3).map do |seat|
        own = hands.fetch(seat, []).map { |code| Card.parse(code) }
        own + rest.shift(Deal::HAND_SIZE - own.size)
      end
      Deal.new(hands: filled, kitty: kitty.map { |code| Card.parse(code) })
    end

    # Seat 1 (forhånd) bids `melding`, everyone else passes.
    def melder_round(hands:, melding: "8vip", kitty: KITTY)
      round = Round.new(rules: Rules.standard, deal: deal_with(hands:, kitty:), dealer: 0)
      play(round, [ 1, bid(melding) ], [ 2, Bidding::Pas.new ], [ 3, Bidding::Pas.new ], [ 0, Bidding::Pas.new ])
    end

    # Plays the runde to its end with the default choices; nobody banks.
    def play_out(round)
      until round.complete?
        step = round.banking? ? [ round.play.melder, CloseBankWindow.new ] : [ round.to_act, round.default_intent(round.to_act) ]
        round = play(round, step)
      end
      round
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
