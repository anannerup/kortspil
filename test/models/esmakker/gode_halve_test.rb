require "test_helper"

module Esmakker
  # Seam 1 for ticket 06: the declaration at gode and halve (REGLER §2.0
  # "Gode", "Halve") through a Round — clubs at gode; at halve the called
  # ace's holder gives herself away to everyone, names trump (not the ace's
  # suit) and takes the kitty, or the melder is selvmakker when the ace lies
  # in the kitty; and the replay from the log.
  #
  # Seat 0 deals, so seat 1 is forhånd; seat 1 bids and the others pass.
  class GodeHalveTest < ActiveSupport::TestCase
    test "at gode clubs are trump for everyone: the melder is never asked, calls the ace and takes the kitty" do
      round = melder_round(hands: { 1 => %w[2C] }, kitty: %w[3D 4D 5D], melding: "8gode")

      assert_equal [ :calling_ace, [ 1 ] ], [ round.phase, round.seats_to_act ]
      (0..3).each do |seat|
        assert_equal "C", round.view_for(seat)[:play][:trump]
        assert_empty round.view_for(seat)[:choices][:trumps]
      end
      assert_equal :not_now, round.apply(1, ChooseTrump.new(trump: Trump.parse("H"))).reason

      called = play(round, [ 1, CallAce.new(suit: "S") ])
      assert_equal [ :discarding, 1, 16 ], [ called.phase, called.to_act, called.view_for(1)[:hand].size ]
      done = play_out(play(called, [ 1, discard("3D", "4D", "5D") ]))
      assert_equal "C", done.result.trump.to_s
    end

    test "halve: the melder first calls an ace she does not hold; nobody names trump before" do
      round = melder_round(hands: { 1 => %w[AH], 2 => %w[AD] }, melding: "8halve")

      assert_equal [ :calling_ace, [ 1 ] ], [ round.phase, round.seats_to_act ]
      assert_equal %w[C D S], round.view_for(1)[:choices][:aces]
      assert_empty round.view_for(1)[:choices][:trumps]
      assert_nil round.view_for(0)[:play][:trump]
      assert_equal :not_now, round.apply(1, ChooseTrump.new(trump: Trump.parse("S"))).reason
      assert_equal :own_ace, round.apply(1, CallAce.new(suit: "H")).reason
      assert_equal :not_your_turn, round.apply(2, CallAce.new(suit: "D")).reason
    end

    test "halve: the ace's holder gives herself away to everyone at once and names trump" do
      round = play(melder_round(hands: { 1 => %w[2D], 2 => %w[AD] }, melding: "8halve"), [ 1, CallAce.new(suit: "D") ])

      assert_equal [ :choosing_trump, [ 2 ] ], [ round.phase, round.seats_to_act ]
      (0..3).each do |seat|
        view = round.view_for(seat)[:play]
        assert_equal [ 2, false, "D" ], view.values_at(:esmakker, :selvmakker, :called_ace), "seat #{seat} knows the esmakker"
        assert_equal({ melder: 0, modspillere: 0 }, view[:side_stik])
      end
      assert_equal 3, round.view_for(0)[:kitty_count], "the kitty is not taken before trump"
      assert_equal %w[C H S trumfloes], round.view_for(2)[:choices][:trumps]
      assert_empty round.view_for(1)[:choices][:trumps], "the melder does not name trump"
      assert_equal :not_your_turn, round.apply(1, ChooseTrump.new(trump: Trump.parse("S"))).reason
    end

    test "halve: trump must not be the called ace's suit; trumfløs may be named" do
      round = play(melder_round(hands: { 2 => %w[AD] }, melding: "8halve"), [ 1, CallAce.new(suit: "D") ])

      assert_equal :trump_is_ace_suit, round.apply(2, ChooseTrump.new(trump: Trump.parse("D"))).reason
      assert round.apply(2, ChooseTrump.new(trump: Trump.trumfloes)).accepted?
      assert round.apply(2, ChooseTrump.new(trump: Trump.parse("H"))).accepted?
    end

    test "halve: the esmakker takes the kitty and lays three away unseen; the melder leads the first stik" do
      round = play(melder_round(hands: { 2 => %w[AD 2S] }, kitty: %w[3C 4C X1], melding: "8halve"),
                   [ 1, CallAce.new(suit: "D") ], [ 2, ChooseTrump.new(trump: Trump.parse("H")) ])

      esmakker = round.view_for(2)
      assert_equal [ :discarding, 2, 16, 0, true ], [ round.phase, round.to_act, esmakker[:hand].size, esmakker[:kitty_count], esmakker[:choices][:discard] ]
      assert_equal %w[3C 4C X1], esmakker[:play][:kitty_cards]
      [ 0, 1, 3 ].each do |seat|
        view = round.view_for(seat)
        assert_equal [ 16, [], false ], [ view[:card_counts][2], view[:play][:kitty_cards], view[:choices][:discard] ]
        assert_not view.to_json.include?("\"X1\""), "seat #{seat} never sees the kitty"
      end
      assert_equal 13, round.view_for(1)[:hand].size, "the melder does not take the kitty at halve"
      assert_equal :not_your_turn, round.apply(1, discard("3C", "4C", "X1")).reason

      laid = play(round, [ 2, discard("2S", "3C", "X1") ])
      assert_equal [ :playing, [ 1 ], 13 ], [ laid.phase, laid.seats_to_act, laid.view_for(2)[:hand].size ]
      assert_equal %w[3C 2S X1], laid.view_for(2)[:play][:discarded]
      [ 0, 1, 3 ].each do |seat|
        assert_empty laid.view_for(seat)[:play][:discarded]
        assert_empty %w[2S 3C X1] & laid.view_for(seat).to_json.scan(/"([2-9TJQKA][CDHS]|X\d)"/).flatten, "seat #{seat} never sees the cards laid away"
      end

      done = play_out(laid)
      assert_equal [ :played, 2, false, "H" ], [ done.result.kind, done.result.esmakker, done.result.selvmakker, done.result.trump.to_s ]
      assert_equal done.result.tricks_won[1] + done.result.tricks_won[2], done.result.stik
      assert_equal 0, done.result.points.sum
      assert_equal done.result.points[1], done.result.points[2], "melder and the halve esmakker win or lose together"
      assert_equal done.result.gik_hjem?, done.result.points[1].positive?
    end

    test "halve with the called ace in the kitty: nobody gives herself away, the melder is selvmakker, names trump and takes the kitty" do
      round = play(melder_round(hands: { 1 => %w[2C] }, kitty: %w[AS 3C 4C], melding: "8halve"), [ 1, CallAce.new(suit: "S") ])

      assert_equal [ :choosing_trump, [ 1 ] ], [ round.phase, round.seats_to_act ]
      (0..3).each do |seat|
        assert_equal [ nil, true ], round.view_for(seat)[:play].values_at(:esmakker, :selvmakker), "seat #{seat} knows she plays alone"
      end
      assert_equal %w[C D H trumfloes], round.view_for(1)[:choices][:trumps]
      assert_equal :trump_is_ace_suit, round.apply(1, ChooseTrump.new(trump: Trump.parse("S"))).reason

      trumped = play(round, [ 1, ChooseTrump.new(trump: Trump.parse("C")) ])
      assert_equal [ :discarding, 1, 16 ], [ trumped.phase, trumped.to_act, trumped.view_for(1)[:hand].size ]
      assert_equal %w[3C 4C AS], trumped.view_for(1)[:play][:kitty_cards]

      done = play_out(play(trumped, [ 1, discard("2C", "3C", "4C") ]))
      result = done.result
      assert_equal [ :played, nil, true, [ 1 ] ], [ result.kind, result.esmakker, result.selvmakker, result.side ]
      assert_equal result.tricks_won[1], result.stik
      over = result.stik - 8
      per_pair = over.negative? ? 1 * -over * 2 : (1 + over) * 2
      sign = result.gik_hjem? ? 1 : -1
      assert_equal [ -sign * per_pair, sign * 3 * per_pair, -sign * per_pair, -sign * per_pair ], result.points,
                   "halve doubles, and the selvmakker settles with each of the three others"
    end

    test "a halve runde is stored as its log and replays to the same state and views" do
      round = play(melder_round(hands: { 3 => %w[AC] }, melding: "9halve"), [ 1, CallAce.new(suit: "C") ], [ 3, ChooseTrump.new(trump: Trump.trumfloes) ])
      done = play_out(play(round, [ 3, Discard.new(cards: round.deal.kitty) ]))

      tokens = done.actions_string.split
      assert_equal %w[1:esC 3:trumftrumfloes], tokens[4, 2]
      assert tokens[6].start_with?("3:kast-")
      rebuilt = Round.from_strings(rules: Rules.standard, deal: done.deal_string, dealer: 0, actions: done.actions_string)
      assert_equal done, rebuilt
      (0..3).each { |seat| assert_equal done.view_for(seat), rebuilt.view_for(seat) }
      assert_raises(ArgumentError) do
        Round.from_strings(rules: Rules.standard, deal: done.deal_string, dealer: 0, actions: "1:9halve 2:pas 3:pas 0:pas 1:esC 3:trumfC")
      end
    end

    test "seeded halve runder played through by the default choices replay from storage" do
      5.times do |seed|
        round = Round.new(rules: Rules.standard, deal: Deal.shuffled(shuffler: Random.new(seed)), dealer: 0)
        done = play_out(play(round, [ 1, bid("8halve") ], [ 2, Bidding::Pas.new ], [ 3, Bidding::Pas.new ], [ 0, Bidding::Pas.new ]))

        assert done.complete?
        assert_not_equal done.result.called_ace, done.result.trump.suit
        assert_equal done, Round.from_strings(rules: Rules.standard, deal: done.deal_string, dealer: 0, actions: done.actions_string)
      end
    end

    private

    def bid(code) = Bidding::Bid.new(melding: Melding.parse(code))
    def discard(*codes) = Discard.new(cards: codes.map { |code| Card.parse(code) })

    # A deal with the given cards in the given hands (and kitty); the rest
    # of the deck fills the other places in order.
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

    # Seat 1 (forhånd) bids `melding`, everyone else passes.
    def melder_round(hands:, melding:, kitty: nil)
      round = Round.new(rules: Rules.standard, deal: deal_with(hands:, kitty:), dealer: 0)
      play(round, [ 1, bid(melding) ], [ 2, Bidding::Pas.new ], [ 3, Bidding::Pas.new ], [ 0, Bidding::Pas.new ])
    end

    # Plays the runde to its end with the default choices.
    def play_out(round)
      round = play(round, [ round.to_act, round.default_intent(round.to_act) ]) until round.complete?
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
