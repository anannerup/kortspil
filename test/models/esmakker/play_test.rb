require "test_helper"

module Esmakker
  # Seam 1 for ticket 03: an ordinary melding played through a Round — the
  # melder's trump and called ace, the kitty, the stik, the hidden
  # esmakker in every seat's view, gik hjem / bet, and the replay.
  #
  # Seat 0 deals, so seat 1 is forhånd; in most tests seat 1 bids and the
  # others pass, so seat 1 is melder.
  class PlayTest < ActiveSupport::TestCase
    HEARTS = %w[2H 3H 4H 5H 6H 7H 8H 9H TH JH QH KH AH].freeze

    test "the melder names any suit or trumfløs, then calls an ace she does not hold" do
      round = melder_round(hands: { 1 => %w[AH AD] }, melding: "9")

      assert_equal :choosing_trump, round.phase
      assert_equal [ 1 ], round.seats_to_act
      assert_equal %w[C D H S trumfloes], round.view_for(1)[:choices][:trumps]
      assert_empty round.view_for(2)[:choices][:trumps]
      assert_equal :not_your_turn, round.apply(2, ChooseTrump.new(trump: Trump.parse("S"))).reason
      assert_equal :unknown_trump, round.apply(1, ChooseTrump.new(trump: nil)).reason
      assert_equal :not_now, round.apply(1, CallAce.new(suit: "C")).reason

      declared = play(round, [ 1, ChooseTrump.new(trump: Trump.trumfloes) ])
      assert_equal :calling_ace, declared.phase
      assert_equal "trumfloes", declared.view_for(3)[:play][:trump]
      assert_equal %w[C S], declared.view_for(1)[:choices][:aces]
      assert_equal :own_ace, declared.apply(1, CallAce.new(suit: "H")).reason
      assert_equal :unknown_ace, declared.apply(1, CallAce.new(suit: "X")).reason
    end

    test "at gode clubs are trump, and the melder only calls the ace" do
      round = melder_round(hands: {}, melding: "8gode")

      assert_equal :calling_ace, round.phase
      assert_equal "C", round.view_for(0)[:play][:trump]
      assert_empty round.view_for(1)[:choices][:trumps]
    end

    test "calling the ace takes the kitty up: the melder alone sees which cards came, and lays any three away unseen" do
      round = play(melder_round(hands: { 1 => %w[2C] }, kitty: %w[3C 4C X1], melding: "8"),
                   [ 1, ChooseTrump.new(trump: Trump.parse("D")) ], [ 1, CallAce.new(suit: "S") ])

      melder = round.view_for(1)
      assert_equal [ :discarding, 16, 0, true ], [ round.phase, melder[:hand].size, melder[:kitty_count], melder[:choices][:discard] ]
      assert_equal %w[3C 4C X1], melder[:play][:kitty_cards]
      other = round.view_for(2)
      assert_equal [ 16, 0, [], false ], [ other[:card_counts][1], other[:kitty_count], other[:play][:kitty_cards], other[:choices][:discard] ]
      assert_not other.to_json.include?("\"X1\""), "nobody else sees the kitty"

      assert_equal :wrong_card_count, round.apply(1, discard("2C", "3C")).reason
      assert_equal :card_not_in_hand, round.apply(1, discard("2C", "3C", "AS")).reason
      assert_equal :duplicate_cards, round.apply(1, discard("2C", "2C", "3C")).reason

      laid = play(round, [ 1, discard("2C", "3C", "X1") ])
      assert_equal [ :playing, 13 ], [ laid.phase, laid.view_for(1)[:hand].size ]
      assert_equal %w[2C 3C X1], laid.view_for(1)[:play][:discarded]
      (0..3).reject { |seat| seat == 1 }.each do |seat|
        view = laid.view_for(seat)
        assert_empty view[:play][:discarded]
        assert_empty %w[2C 3C X1] & view.to_json.scan(/"([2-9TJQKA][CDHS]|X\d)"/).flatten, "the cards laid away stay hidden from seat #{seat}"
      end

      kept = play(round, [ 1, discard("3C", "4C", "X1") ])
      assert_equal :playing, kept.phase, "she may lay the kitty's own three back"
    end

    test "the melder leads the first stik; follow suit if you can; a joker may be played at any time" do
      round = ready_to_play(hands: { 1 => %w[2S 3S 4S], 2 => %w[KS 5D X2], 3 => %w[6D 7D 8D 9D TD JD QD KD AD 2D 3D 4D 5C] })

      assert_equal [ 1 ], round.seats_to_act
      assert_equal round.view_for(1)[:hand].sort, round.view_for(1)[:play][:legal_moves].sort, "any card to lead"
      assert_empty round.view_for(2)[:play][:legal_moves]

      led = play(round, [ 1, card("2S") ])
      spades_or_jokers = led.view_for(2)[:hand].select { |code| code.end_with?("S") || code.start_with?("X") }
      assert_includes spades_or_jokers, "X2"
      assert_equal spades_or_jokers.sort, led.view_for(2)[:play][:legal_moves].sort, "follow spades, or a joker"
      assert_equal :must_follow_suit, led.apply(2, PlayCard.new(card: Card.parse("5D"))).reason
      assert_equal :card_not_in_hand, led.apply(2, PlayCard.new(card: Card.parse("2C"))).reason

      followed = play(led, [ 2, card("KS") ])
      assert_equal followed.view_for(3)[:hand].sort, followed.view_for(3)[:play][:legal_moves].sort, "void in spades: anything"
    end

    test "after a led joker, the first playing card sets the suit to follow, and the led joker wins" do
      trick = Trick.lead(0).add(0, Card.parse("X1"))
      assert_nil trick.led_suit
      hand = %w[2S 3D X2].map { |code| Card.parse(code) }
      assert_equal hand, LegalMoves.for(hand:, trick:)

      trick = trick.add(1, Card.parse("AS"))
      assert_equal %w[2S X2], LegalMoves.for(hand:, trick:).map(&:to_s)
      trick = trick.add(2, Card.parse("2S")).add(3, Card.parse("2H"))
      assert_equal 0, trick.winner(Trump.parse("H"))
    end

    test "trump beats the led suit; trumfløs has no trump; a joker not led is worth nothing" do
      trick = Trick.new(leader: 2, plays: [ [ 2, Card.parse("KS") ], [ 3, Card.parse("2H") ], [ 0, Card.parse("AS") ], [ 1, Card.parse("X3") ] ])

      assert_equal 3, trick.winner(Trump.parse("H"))
      assert_equal 0, trick.winner(Trump.trumfloes)
      assert_equal 0, trick.winner(Trump.parse("C"))
    end

    test "the winner of a stik leads the next" do
      round = ready_to_play(hands: { 1 => %w[2S], 2 => %w[AS], 3 => %w[3S], 0 => %w[4S] })

      after = play(round, [ 1, card("2S") ], [ 2, card("AS") ], [ 3, card("3S") ], [ 0, card("4S") ])

      view = after.view_for(0)[:play]
      assert_equal [ 2, [ 0, 0, 1, 0 ], [] ], [ view[:last_trick_winner], view[:tricks_won], view[:current_trick] ]
      assert_equal %w[2S AS 3S 4S], view[:last_trick].map { |play| play[:card] }
      assert_equal [ 2 ], after.seats_to_act
    end

    test "the esmakker stays hidden until the called ace is played; only she knows it before" do
      round = ready_to_play(hands: { 1 => %w[2D], 2 => %w[AD 3D], 3 => %w[4D], 0 => %w[5D] }, ace: "D")

      assert_equal 2, round.view_for(2)[:play][:esmakker], "she knows she holds the ace"
      [ 0, 1, 3 ].each do |seat|
        view = round.view_for(seat)
        assert_equal [ nil, false, nil, "D" ], view[:play].values_at(:esmakker, :selvmakker, :side_stik, :called_ace)
        assert_not view.to_json.include?("\"AD\""), "seat #{seat} sees no trace of the ace"
      end

      played = play(round, [ 1, card("2D") ], [ 2, card("AD") ])
      (0..3).each { |seat| assert_equal 2, played.view_for(seat)[:play][:esmakker] }
      done = play(played, [ 3, card("4D") ], [ 0, card("5D") ])
      assert_equal({ melder: 1, modspillere: 0 }, done.view_for(0)[:play][:side_stik])
    end

    test "the called ace in the kitty: the melder is selvmakker, knows it at once, and the others learn it at the end" do
      round = ready_to_play(hands: { 1 => HEARTS.first(12) + %w[2C] }, kitty: %w[AS 3C 4C], ace: "S", trump: "H", discard: %w[2C 3C 4C], melding: "8")

      assert round.view_for(1)[:play][:selvmakker]
      assert_nil round.view_for(1)[:play][:esmakker]
      assert_not round.view_for(2)[:play][:selvmakker]

      done = play_out(round)
      result = done.result
      assert_equal [ :played, nil, true, 1 ], [ result.kind, result.esmakker, result.selvmakker, result.melder ]
      assert_equal done.view_for(1)[:play][:tricks_won][1], result.stik, "the selvmakker counts her own stik alone"
      assert result.gik_hjem?
      assert done.view_for(3)[:play][:selvmakker], "everyone knows once the runde is over"
    end

    test "a melder holding all four aces may call any of them and is selvmakker" do
      round = play(melder_round(hands: { 1 => %w[AC AD AH AS] }, melding: "8"), [ 1, ChooseTrump.new(trump: Trump.parse("S")) ])

      assert_equal %w[C D H S], round.view_for(1)[:choices][:aces]
      called = play(round, [ 1, CallAce.new(suit: "H") ])
      assert called.view_for(1)[:play][:selvmakker]
    end

    test "the melding gik hjem with at least its number of stik for melder and esmakker together, and is bet with fewer" do
      home = play_out(ready_to_play(hands: { 1 => HEARTS }, ace: "S", trump: "H", melding: "13"))
      assert_equal [ true, 13 ], [ home.result.gik_hjem?, home.result.stik ]
      assert_equal :complete, home.phase
      assert_empty home.seats_to_act
      assert_equal({ gik_hjem: true, stik: 13 }, home.view_for(0)[:result].slice(:gik_hjem, :stik))

      weak = %w[2H 3H 4H 5H 6H 7H 8H 2D 3D 4D 5D 6D 7D]
      bet = play_out(ready_to_play(hands: { 1 => weak, 2 => %w[AS] }, ace: "S", trump: "H", melding: "13"))
      result = bet.result
      assert_not result.gik_hjem?
      assert_equal 2, result.esmakker
      assert_equal result.tricks_won[1] + result.tricks_won[2], result.stik
      assert_operator result.stik, :<, 13
      assert_equal 13, result.tricks_won.sum
      lost = 3.5 * (13 - result.stik)
      assert_equal [ lost, -lost, -lost, lost ].map { |amount| Scoring.tidy(Scoring.exact(amount)) }, result.points, "melder and esmakker each pay 3.5 per missing stik"
    end

    test "a played runde is stored as its log and replays to the same state and views" do
      done = play_out(ready_to_play(hands: {}, ace: "S", trump: "trumfloes"))

      tokens = done.actions_string.split.map { |entry| entry.split(":").last }
      assert_includes tokens, "trumftrumfloes"
      assert_includes tokens, "esS"
      assert(tokens.any? { |token| token.start_with?("kast-") })
      rebuilt = Round.from_strings(rules: Rules.standard, deal: done.deal_string, dealer: 0, actions: done.actions_string)
      assert_equal done, rebuilt
      (0..3).each { |seat| assert_equal done.view_for(seat), rebuilt.view_for(seat) }
      assert_raises(ArgumentError) { Round.from_strings(rules: Rules.standard, deal: done.deal_string, dealer: 0, actions: "1:2C") }
    end

    test "seeded runder played through by the default choices replay from storage" do
      5.times do |seed|
        round = Round.new(rules: Rules.standard, deal: Deal.shuffled(shuffler: Random.new(seed)), dealer: seed % 4)
        round = play(round, [ round.forhand, bid("8") ], *Seats::ALL.reject { |seat| seat == round.forhand }.map { |seat| [ seat, Bidding::Pas.new ] }.sort_by { |seat, _| (seat - round.forhand) % 4 })
        done = play_out(round)

        assert done.complete?
        assert_equal 13, done.result.tricks_won.sum
        assert_equal done, Round.from_strings(rules: Rules.standard, deal: done.deal_string, dealer: seed % 4, actions: done.actions_string)
      end
    end

    private

    def bid(code) = Bidding::Bid.new(melding: Melding.parse(code))
    def card(code) = PlayCard.new(card: Card.parse(code))
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

    # Seat 1 is melder, has named trump, called the ace (default: the first
    # she may) and laid away `discard` (default: the kitty back).
    def ready_to_play(hands:, ace: nil, trump: "S", kitty: nil, discard: nil, melding: "8")
      round = play(melder_round(hands:, melding:, kitty:), [ 1, ChooseTrump.new(trump: Trump.parse(trump)) ])
      round = play(round, [ 1, CallAce.new(suit: ace || round.view_for(1)[:choices][:aces].first) ])
      cards = discard ? discard.map { |code| Card.parse(code) } : round.deal.kitty
      play(round, [ 1, Discard.new(cards:) ])
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
