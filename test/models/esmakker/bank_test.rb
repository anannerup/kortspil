require "test_helper"

module Esmakker
  # Seam 1 for ticket 08: bank i bordet (REGLER §2.0) through a Round. Only
  # at vip, in the window after trump is named and before the melder takes
  # the kitty up: the first bank is not the melder's (the esmakker's only
  # when the bord allows it), then only the melder banks once more, at most
  # two; each bank doubles gevinst and bet; the option looks the same to the
  # three non-melders; and the log replays.
  #
  # Seat 0 deals, so seat 1 is forhånd; seat 1 bids and the others pass.
  # Seat 2 holds the ace of diamonds: the esmakker when it is called.
  class BankTest < ActiveSupport::TestCase
    KITTY = %w[5D QS 9H].freeze
    CLOSE = [ 1, CloseBankWindow.new ].freeze

    test "the window opens when vip's trump is named, before the kitty: nobody is to act, and the three non-melders are offered Bank alike" do
      round = trump_named

      assert_equal [ :banking, [], nil, 3 ], [ round.phase, round.seats_to_act, round.to_act, round.view_for(1)[:kitty_count] ]
      assert_equal({ 0 => true, 1 => false, 2 => true, 3 => true }, (0..3).to_h { |seat| [ seat, round.view_for(seat)[:choices][:bank] ] })
      (0..3).each { |seat| assert_equal [ true, [] ], round.view_for(seat)[:play].values_at(:bank_window, :banks) }
      assert_empty round.view_for(1)[:play][:kitty_cards], "she takes the kitty up when the window closes"
      assert_nil round.default_intent(0), "a bot never banks"
      assert_equal :not_your_turn, round.apply(1, Discard.new(cards: round.deal.kitty)).reason
      assert_equal :not_your_turn, round.apply(1, PlayCard.new(card: round.play.hand(1).first)).reason
    end

    test "the melder may not bank first; a modspiller banks, then only the melder, which closes the window: ×4" do
      round = trump_named
      assert_equal :melder_banks_second, round.apply(1, Bank.new).reason

      once = play(round, [ 3, Bank.new ])
      assert_equal [ :banking, [ 3 ] ], [ once.phase, once.play.banks ]
      assert_equal({ 0 => false, 1 => true, 2 => false, 3 => false }, (0..3).to_h { |seat| [ seat, once.view_for(seat)[:choices][:bank] ] })
      [ 0, 2, 3 ].each { |seat| assert_equal :only_melder_banks_again, once.apply(seat, Bank.new).reason }

      twice = play(once, [ 1, Bank.new ])
      assert_equal [ :discarding, [ 3, 1 ], [ 1 ] ], [ twice.phase, twice.play.banks, twice.seats_to_act ]
      (0..3).each { |seat| assert_equal [ false, [ 3, 1 ] ], twice.view_for(seat)[:play].values_at(:bank_window, :banks) }
      (0..3).each { |seat| assert_equal :not_now, twice.apply(seat, Bank.new).reason, "at most two banks" }
      assert_equal :not_now, twice.apply(1, CloseBankWindow.new).reason

      done = play_out(play(twice, [ 1, Discard.new(cards: twice.deal.kitty) ]))
      assert_equal 2, done.result.banks
      assert_points done.result, factor: 2 * 4
    end

    test "one bank and the time runs out: ×2 on top of the vip card" do
      round = play(trump_named(turns: 2), [ 0, Bank.new ], CLOSE)
      assert_equal [ :discarding, [ 0 ] ], [ round.phase, round.play.banks ]
      assert_equal :not_now, round.apply(1, Bank.new).reason, "the melder's answer comes in the window"

      done = play_out(play(round, [ 1, Discard.new(cards: round.deal.kitty) ]))
      assert_equal [ 1, 2 ], [ done.result.banks, done.result.vip_card ]
      assert_points done.result, factor: 4 * 2
    end

    test "nobody banks: the window closes when the time runs out, and the points are the vip card's alone" do
      round = play(trump_named, CLOSE)
      assert_equal [ :discarding, [], 16 ], [ round.phase, round.play.banks, round.view_for(1)[:hand].size ]
      assert_equal :not_now, round.apply(2, Bank.new).reason
      assert_equal :not_your_turn, trump_named.apply(2, CloseBankWindow.new).reason, "the window is closed for the melder's seat"

      done = play_out(play(round, [ 1, Discard.new(cards: round.deal.kitty) ]))
      assert_equal 0, done.result.banks
      assert_points done.result, factor: 2
    end

    test "the esmakker may bank first when the bord allows it (the standard)" do
      round = play(trump_named, [ 2, Bank.new ])
      assert_equal [ 2 ], round.play.banks
    end

    test "when the bord forbids it, the esmakker is still offered Bank, but her first bank is refused; a modspiller's is not" do
      rules = Rules.new(esmakker_banks_first: false)
      round = trump_named(rules:)

      assert round.view_for(2)[:choices][:bank], "the option looks the same as the modspillere's"
      assert_equal round.view_for(0)[:choices], round.view_for(2)[:choices]
      assert_equal :esmakker_banks_first_not_allowed, round.apply(2, Bank.new).reason

      once = play(round, [ 0, Bank.new ])
      assert_equal :only_melder_banks_again, once.apply(2, Bank.new).reason
      assert_equal [ 0, 1 ], play(once, [ 1, Bank.new ]).play.banks
    end

    test "a selvmakker (the called ace in the kitty, not turned) may be banked against by all three" do
      rules = Rules.new(esmakker_banks_first: false)
      round = play(melder_round(hands: {}, kitty: %w[5D QS AH], rules:), [ 1, CallAce.new(suit: "H") ], [ 1, TurnCard.new ], [ 1, AcceptTrump.new ])

      assert_nil round.play.esmakker
      [ 0, 2, 3 ].each { |seat| assert round.apply(seat, Bank.new).accepted?, "seat #{seat}" }
    end

    test "a bet doubles too: each bank ×2 on the missing stik" do
      result = RundeResult.played(melder: 1, melding: Melding.parse("8vip"), trump: Trump.parse("S"), called_ace: "D", esmakker: 2, selvmakker: false,
                                  tricks_won: [ 4, 3, 2, 4 ], values: Points.standard, vip_card: 1, banks: 2)
      # 3 missing stik × stake 1 × vip first card 2 × two banks 4.
      assert_equal [ 24, -24, -24, 24 ], result.points
      assert_equal 2, result.to_h[:banks]
    end

    test "no bank at the other meldinger: not at an ordinary melding, gode or halve" do
      ordinary = play(melder_round(hands: { 2 => %w[AD] }, melding: "8"), [ 1, ChooseTrump.new(trump: Trump.parse("S")) ], [ 1, CallAce.new(suit: "D") ])
      gode = play(melder_round(hands: { 2 => %w[AD] }, melding: "8gode"), [ 1, CallAce.new(suit: "D") ])
      halve = play(melder_round(hands: { 2 => %w[AD] }, melding: "8halve"), [ 1, CallAce.new(suit: "D") ], [ 2, ChooseTrump.new(trump: Trump.parse("S")) ])

      [ ordinary, gode, halve ].each do |round|
        assert_equal :discarding, round.phase
        (0..3).each do |seat|
          assert_equal :not_now, round.apply(seat, Bank.new).reason
          assert_not round.view_for(seat)[:choices][:bank]
        end
        done = play_out(round)
        assert_equal [ 0, [] ], [ done.result.banks, done.play.banks ]
      end
      assert_equal :not_now, melder_round(hands: { 2 => %w[AD] }).apply(0, Bank.new).reason, "nor in the vip runde before trump"
    end

    test "banks are logged and replay to the same state, views and points" do
      done = play_out(play(trump_named, [ 3, Bank.new ], [ 1, Bank.new ]))
      tokens = done.actions_string.split
      assert_equal %w[1:accepter 3:bank 1:bank], tokens[6..8]

      rebuilt = Round.from_strings(rules: Rules.standard, deal: done.deal_string, dealer: 0, actions: done.actions_string)
      assert_equal done, rebuilt
      assert_equal done.result, rebuilt.result
      (0..3).each { |seat| assert_equal done.view_for(seat), rebuilt.view_for(seat) }

      timed_out = play_out(play(trump_named, CLOSE))
      assert_includes timed_out.actions_string.split, "1:bankslut"
      assert_equal timed_out, Round.from_strings(rules: Rules.standard, deal: timed_out.deal_string, dealer: 0, actions: timed_out.actions_string)

      prefix = "1:8vip 2:pas 3:pas 0:pas 1:esD 1:vend 1:accepter"
      assert_raises(ArgumentError) { Round.from_strings(rules: Rules.standard, deal: done.deal_string, dealer: 0, actions: "#{prefix} 1:bank") }
      assert_raises(ArgumentError) { Round.from_strings(rules: Rules.standard, deal: done.deal_string, dealer: 0, actions: "#{prefix} 0:bank 2:bank") }
      assert_raises(ArgumentError) { Round.from_strings(rules: Rules.standard, deal: done.deal_string, dealer: 0, actions: "#{prefix} 0:bank 1:bank 1:bank") }
      assert_raises(ArgumentError) { Round.from_strings(rules: Rules.new(esmakker_banks_first: false), deal: done.deal_string, dealer: 0, actions: "#{prefix} 2:bank") }
    end

    private

    def bid(code) = Bidding::Bid.new(melding: Melding.parse(code))

    # A vip runde with trump just named from the kitty's `turns`th card: the
    # bank window is open. Seat 2 is the esmakker (ace of diamonds).
    def trump_named(turns: 1, rules: Rules.standard)
      round = play(melder_round(hands: { 2 => %w[AD] }, rules:), [ 1, CallAce.new(suit: "D") ], *[ [ 1, TurnCard.new ] ] * turns)
      turns == 3 ? round : play(round, [ 1, AcceptTrump.new ])
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

    # Seat 1 (forhånd) bids `melding`, everyone else passes.
    def melder_round(hands:, melding: "8vip", kitty: KITTY, rules: Rules.standard)
      round = Round.new(rules:, deal: deal_with(hands:, kitty:), dealer: 0)
      play(round, [ 1, bid(melding) ], [ 2, Bidding::Pas.new ], [ 3, Bidding::Pas.new ], [ 0, Bidding::Pas.new ])
    end

    # Plays the runde to its end with the default choices; the window, if
    # open, runs out.
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
