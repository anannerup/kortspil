require "test_helper"

module Esmakker
  # Seam 1 for ticket 04: the called ace (the esmakker must lay it the
  # first time its suit is led; "esset må ikke stikkes"), the jokers with
  # the bord's trump setting, and fordækt, through a Round, plus the stik
  # rules at the Trick / LegalMoves level for the cases a deal makes long.
  #
  # Seat 0 deals, so seat 1 is forhånd and, here, always the melder.
  class AceJokersFordaektTest < ActiveSupport::TestCase
    # Trump spades, the diamond ace called: seat 2 holds it, seat 3 is void
    # in diamonds and holds spades (trump), seat 0 has diamonds.
    ACE_HANDS = {
      1 => %w[2D AS KS QS AH KH QH JH AC KC QC JC TC],
      2 => %w[AD 3D X1 2H 3H 4H 5H 6H 7H 8H 9H TH 2C],
      3 => %w[2S 3S 4S 5S 6S 3C 4C 5C 6C 7C 8C 9C X2]
    }.freeze
    ACE_KITTY = %w[9S TS JS].freeze

    # The melder (seat 1) has no diamonds after the kitty; seat 2 holds the
    # diamond ace, seat 3 one diamond, seat 0 the rest of them.
    FORDAEKT_HANDS = {
      1 => %w[AS KS QS AH KH QH JH AC KC QC JC TC 9C],
      2 => %w[AD 3D 2H 3H 4H 5H 6H 7H 8H 9H TH 5C 6C],
      3 => %w[4D 2S 3S 4S 5S 6S 7S 8S 9S TS 7C 8C X2]
    }.freeze
    FORDAEKT_KITTY = %w[2C 3C X3].freeze

    # --- The called ace ---

    test "the esmakker must lay the called ace the first time its suit is led, not another card of it, nor a joker" do
      round = ready(hands: ACE_HANDS, kitty: ACE_KITTY)
      led = play(round, [ 1, card("2D") ])

      assert_equal %w[AD], led.view_for(2)[:play][:legal_moves]
      assert_equal :must_play_ace, led.apply(2, card("3D")).reason
      assert_equal :must_play_ace, led.apply(2, card("X1")).reason
      assert_equal 2, play(led, [ 2, card("AD") ]).view_for(0)[:play][:esmakker]
    end

    test "once the ace lies in the stik, a seat void in its suit may not trump it; the ace takes the stik" do
      round = play(ready(hands: ACE_HANDS, kitty: ACE_KITTY), [ 1, card("2D") ], [ 2, card("AD") ])

      legal = round.view_for(3)[:play][:legal_moves]
      assert_equal %w[3C 4C 5C 6C 7C 8C 9C X2], legal, "clubs or the joker, no spade"
      assert_equal :may_not_trump_ace, round.apply(3, card("2S")).reason
      followed = play(round, [ 3, card("3C") ])
      assert(followed.view_for(0)[:play][:legal_moves].all? { |code| code.end_with?("D") || code.start_with?("X") }, "a seat with the suit follows it as usual")

      taken = play(followed, [ 0, card("4D") ])
      assert_equal 2, taken.view_for(1)[:play][:last_trick_winner]
    end

    test "a seat void in the suit that plays before the ace may trump, but the ace still takes the stik" do
      hands = { 1 => ACE_HANDS[1], 2 => ACE_HANDS[3], 3 => ACE_HANDS[2] }
      round = play(ready(hands:, kitty: ACE_KITTY), [ 1, card("2D") ])

      assert_includes round.view_for(2)[:play][:legal_moves], "2S", "the ace has not fallen yet"
      taken = play(round, [ 2, card("2S") ], [ 3, card("AD") ], [ 0, card("4D") ])
      assert_equal 3, taken.view_for(1)[:play][:last_trick_winner]
    end

    test "a selvmakker is not bound by the ace rules: she may hold the ace back when its suit is led" do
      hands = { 1 => %w[2C 2H 3H 4H 5H 6H 7H 8H 9H TH JH QH KH] }
      round = ready(hands:, kitty: %w[AD 4D 5D], ace: "D", trump: "H", discard: %w[2C 2H 3H])
      assert round.view_for(1)[:play][:selvmakker]

      # Seat 2 takes the first stik with the heart ace and leads diamonds.
      round = play(round, [ 1, card("KH") ], [ 2, card("AH") ], [ 3, card("5S") ], [ 0, card("3C") ])
      round = play(round, [ 2, card("3D") ], [ 3, card("6S") ], [ 0, card("2D") ])

      assert_equal %w[4D 5D AD], round.view_for(1)[:play][:legal_moves].sort
      assert_includes play(round, [ 1, card("4D") ]).view_for(1)[:hand], "AD", "she held the ace back"
    end

    test "the ace rules at the stik's level: not after a led joker, not for a selvmakker, only trump when it is all you hold" do
      joker_led = Trick.lead(1).add(1, Card.parse("X1"))
      hand = cards(%w[AD 3D 2H])
      assert_equal hand, LegalMoves.for(hand:, trick: joker_led, trump: Trump.parse("S"), called_ace: "D"), "a led joker is not a lead in diamonds"
      set = joker_led.add(2, Card.parse("5D"))
      assert_equal cards(%w[AD 3D]), LegalMoves.for(hand:, trick: set, trump: Trump.parse("S"), called_ace: "D"), "after it the diamonds are followed as usual"

      led = Trick.lead(1).add(1, Card.parse("2D"))
      assert_equal cards(%w[AD 3D]), LegalMoves.for(hand:, trick: led, trump: Trump.parse("S"), called_ace: nil), "no esmakker: no ace rule"

      ace_down = led.add(2, Card.parse("AD"))
      only_trump = cards(%w[2S 3S])
      assert_equal only_trump, LegalMoves.for(hand: only_trump, trick: ace_down, trump: Trump.parse("S"), called_ace: "D")
      complete = ace_down.add(3, Card.parse("2S")).add(0, Card.parse("4D"))
      assert_equal 2, complete.winner(Trump.parse("S"), called_ace: "D")
      assert_equal 3, complete.winner(Trump.parse("S"), called_ace: nil), "without an esmakker the ace is trumped like any card"
      assert_equal cards(%w[2S 3S 2H]), LegalMoves.for(hand: cards(%w[2S 3S 2H]), trick: ace_down, trump: Trump.trumfloes, called_ace: "D"), "trumfløs: nothing to trump with"
    end

    # --- Jokers ---

    test "a led joker wins the stik and cannot be trumped by default; with the bord's setting the highest trump beats it" do
      steps = [ [ 1, card("X3") ], [ 2, card("2H") ], [ 3, card("2S") ], [ 0, card("5D") ] ]

      standard = play(ready(hands: FORDAEKT_HANDS, kitty: FORDAEKT_KITTY, discard: %w[2C 3C TC]), *steps)
      assert_equal 1, standard.view_for(0)[:play][:last_trick_winner]

      trumpable = play(ready(hands: FORDAEKT_HANDS, kitty: FORDAEKT_KITTY, discard: %w[2C 3C TC], rules: Rules.new(joker_trumpable: true)), *steps)
      assert_equal 3, trumpable.view_for(0)[:play][:last_trick_winner]
      assert_equal [ 0, 0, 0, 1 ], trumpable.view_for(0)[:play][:tricks_won]
    end

    test "jokers at the stik's level: a led joker with no trump in the stik wins also when trumpable; a joker not led is worth nothing" do
      spades = Trump.parse("S")
      no_trump = Trick.new(leader: 0, plays: [ [ 0, Card.parse("X1") ], [ 1, Card.parse("AH") ], [ 2, Card.parse("X2") ], [ 3, Card.parse("KH") ] ])
      assert_equal 0, no_trump.winner(spades, joker_trumpable: true)

      two_trumps = Trick.new(leader: 0, plays: [ [ 0, Card.parse("X1") ], [ 1, Card.parse("3S") ], [ 2, Card.parse("KS") ], [ 3, Card.parse("AH") ] ])
      assert_equal 0, two_trumps.winner(spades)
      assert_equal 2, two_trumps.winner(spades, joker_trumpable: true)
      assert_equal 0, two_trumps.winner(Trump.trumfloes, joker_trumpable: true), "trumfløs: nothing beats the joker"

      not_led = Trick.new(leader: 0, plays: [ [ 0, Card.parse("2H") ], [ 1, Card.parse("X1") ], [ 2, Card.parse("3H") ], [ 3, Card.parse("X2") ] ])
      assert_equal 2, not_led.winner(spades, joker_trumpable: true)
    end

    # --- Fordækt ---

    test "a melder void in the ace's suit after the kitty may lay one card fordækt, never a joker, before she leads" do
      round = ready(hands: FORDAEKT_HANDS, kitty: FORDAEKT_KITTY, discard: %w[2C 3C TC])

      offered = round.view_for(1)[:choices][:fordaekt]
      assert_equal (round.view_for(1)[:hand] - %w[X3]).sort, offered.sort, "any card of her hand but the joker"
      [ 0, 2, 3 ].each { |seat| assert_empty round.view_for(seat)[:choices][:fordaekt] }
      assert_equal :joker_fordaekt, round.apply(1, LayFordaekt.new(card: Card.parse("X3"))).reason
      assert_equal :card_not_in_hand, round.apply(1, LayFordaekt.new(card: Card.parse("AD"))).reason
      assert_equal :not_your_turn, round.apply(2, LayFordaekt.new(card: Card.parse("AD"))).reason
      assert_kind_of PlayCard, round.default_intent(1), "a seat that acts without choosing never lays fordækt"

      laid = play(round, [ 1, LayFordaekt.new(card: Card.parse("9C")) ])
      assert_equal [ 12, 1 ], [ laid.view_for(1)[:hand].size, laid.to_act ]
      assert_empty laid.view_for(1)[:choices][:fordaekt], "only one card"
      assert_includes laid.view_for(1)[:play][:legal_moves], "9C", "she may lead it at once, or later"
      assert_equal({ seat: 1, card: "9C", waiting: true, turned: false }, laid.view_for(1)[:play][:fordaekt])
      [ 0, 2, 3 ].each do |seat|
        view = laid.view_for(seat)
        assert_equal({ seat: 1, card: nil, waiting: true, turned: false }, view[:play][:fordaekt])
        assert_equal 12, view[:card_counts][1]
        assert_not view.to_json.include?("\"9C\""), "seat #{seat} sees only the card's back"
      end
    end

    test "fordækt only when void in the ace's suit, with an esmakker, and before the first card" do
      holding = ready(hands: ACE_HANDS, kitty: ACE_KITTY)
      assert_empty holding.view_for(1)[:choices][:fordaekt]
      assert_equal :fordaekt_not_allowed, holding.apply(1, LayFordaekt.new(card: Card.parse("TC"))).reason

      hands = { 1 => %w[2C 2H 3H 4H 5H 6H 7H 8H 9H TH JH QH KH] }
      selvmakker = ready(hands:, kitty: %w[AD 4D 5D], ace: "D", trump: "H", discard: %w[AD 4D 5D])
      assert selvmakker.view_for(1)[:play][:selvmakker]
      assert_equal :fordaekt_not_allowed, selvmakker.apply(1, LayFordaekt.new(card: Card.parse("2C"))).reason

      round = ready(hands: FORDAEKT_HANDS, kitty: FORDAEKT_KITTY, discard: %w[2C 3C TC])
      after = play(round, [ 1, card("AS") ], [ 2, card("2H") ], [ 3, card("2S") ], [ 0, card("JS") ])
      assert_equal 1, after.to_act
      assert_empty after.view_for(1)[:choices][:fordaekt]
      assert_equal :not_now, after.apply(1, LayFordaekt.new(card: Card.parse("9C"))).reason
      assert_equal :not_now, play(round, [ 1, LayFordaekt.new(card: Card.parse("9C")) ]).apply(1, LayFordaekt.new(card: Card.parse("AC"))).reason
    end

    test "at halve the melder never takes the kitty: void in the ace's suit in her own hand, she may lay a card fordækt" do
      round = Round.new(rules: Rules.standard, deal: deal_with(hands: FORDAEKT_HANDS, kitty: FORDAEKT_KITTY), dealer: 0)
      round = play(round, [ 1, bid("8halve") ], [ 2, Bidding::Pas.new ], [ 3, Bidding::Pas.new ], [ 0, Bidding::Pas.new ])
      round = play(round, [ 1, CallAce.new(suit: "D") ], [ 2, ChooseTrump.new(trump: Trump.parse("S")) ], [ 2, Discard.new(cards: cards(FORDAEKT_KITTY)) ])

      assert_equal [ :playing, 1 ], [ round.phase, round.to_act ]
      assert_equal FORDAEKT_HANDS[1].sort, round.view_for(1)[:choices][:fordaekt].sort
      laid = play(round, [ 1, LayFordaekt.new(card: Card.parse("9C")) ], [ 1, card("9C") ])
      assert_equal %w[AD], laid.view_for(2)[:play][:legal_moves]
    end

    test "led, the fordækt card counts as the ace's suit: the esmakker lays the ace, the others follow it, and it is turned once the stik is taken" do
      round = play(ready(hands: FORDAEKT_HANDS, kitty: FORDAEKT_KITTY, discard: %w[2C 3C TC]), [ 1, LayFordaekt.new(card: Card.parse("9C")) ])

      led = play(round, [ 1, card("9C") ])
      assert_equal [ { seat: 1, card: "9C", fordaekt: true } ], led.view_for(1)[:play][:current_trick]
      [ 0, 2, 3 ].each { |seat| assert_equal [ { seat: 1, card: "fordaekt", fordaekt: true } ], led.view_for(seat)[:play][:current_trick] }
      assert_equal %w[AD], led.view_for(2)[:play][:legal_moves]

      aced = play(led, [ 2, card("AD") ])
      assert_equal %w[4D X2], aced.view_for(3)[:play][:legal_moves], "seat 3 follows diamonds (or a joker)"
      assert_not aced.view_for(3).to_json.include?("\"9C\""), "still face down while the stik is open"

      taken = play(aced, [ 3, card("4D") ], [ 0, card("2D") ])
      (0..3).each do |seat|
        view = taken.view_for(seat)[:play]
        assert_equal({ seat: 1, card: "9C", fordaekt: true }, view[:last_trick].first, "turned for seat #{seat}")
        assert_equal({ seat: 1, card: "9C", waiting: false, turned: true }, view[:fordaekt])
        assert_equal 2, view[:last_trick_winner]
      end
    end

    test "the fordækt card is the melder's card of the ace's suit wherever it is played, and ranks below every card of it" do
      fordaekt = FordaektCard.new(card: Card.parse("9C"), suit: "D")
      hand = [ fordaekt, *cards(%w[2H 3S]) ]

      diamonds = Trick.lead(2).add(2, Card.parse("3D"))
      assert_equal [ fordaekt ], LegalMoves.for(hand:, trick: diamonds, trump: Trump.parse("S"), called_ace: "D"), "she follows the ace's suit with it"
      clubs = Trick.lead(2).add(2, Card.parse("2C"))
      assert_equal hand, LegalMoves.for(hand:, trick: clubs, trump: Trump.parse("S"), called_ace: "D"), "void in clubs, it is a discard like any other"

      led = Trick.new(leader: 1, plays: [ [ 1, fordaekt ], [ 2, Card.parse("2D") ], [ 3, Card.parse("2H") ], [ 0, Card.parse("3H") ] ])
      assert_equal 2, led.winner(Trump.parse("S")), "any real diamond beats it"
    end

    test "a runde with fordækt is stored as its log and replays to the same state and views" do
      round = play(ready(hands: FORDAEKT_HANDS, kitty: FORDAEKT_KITTY, discard: %w[2C 3C TC]), [ 1, LayFordaekt.new(card: Card.parse("9C")) ], [ 1, card("9C") ])
      done = play_out(round)

      assert_includes done.actions_string.split, "1:fordaekt-9C"
      rebuilt = Round.from_strings(rules: Rules.standard, deal: done.deal_string, dealer: 0, actions: done.actions_string)
      assert_equal done, rebuilt
      (0..3).each { |seat| assert_equal done.view_for(seat), rebuilt.view_for(seat) }
      assert_equal 13, done.result.tricks_won.sum
      assert_raises(ArgumentError) { Round.from_strings(rules: Rules.standard, deal: done.deal_string, dealer: 0, actions: done.actions_string.sub("1:fordaekt-9C", "1:fordaekt-X3")) }
    end

    test "seeded runder with jokers beatable by trump play through and replay from storage" do
      rules = Rules.new(joker_trumpable: true)
      5.times do |seed|
        round = Round.new(rules:, deal: Deal.shuffled(shuffler: Random.new(seed)), dealer: 0)
        round = play(round, [ 1, bid("8") ], [ 2, Bidding::Pas.new ], [ 3, Bidding::Pas.new ], [ 0, Bidding::Pas.new ])
        done = play_out(round)

        assert_equal 13, done.result.tricks_won.sum
        assert_equal done, Round.from_strings(rules:, deal: done.deal_string, dealer: 0, actions: done.actions_string)
      end
    end

    private

    def bid(code) = Bidding::Bid.new(melding: Melding.parse(code))
    def card(code) = PlayCard.new(card: Card.parse(code))
    def cards(codes) = codes.map { |code| Card.parse(code) }

    # A deal with the given cards in the given hands and kitty; the rest of
    # the deck fills the other places in order.
    def deal_with(hands:, kitty:)
      placed = (hands.values.flatten + kitty).map { |code| Card.parse(code) }
      rest = Card.deck - placed
      filled = (0..3).map do |seat|
        own = cards(hands.fetch(seat, []))
        own + rest.shift(Deal::HAND_SIZE - own.size)
      end
      Deal.new(hands: filled, kitty: cards(kitty))
    end

    # Seat 1 bids 8 and the others pass; she names `trump`, calls `ace`
    # and lays `discard` away (default: the kitty back).
    def ready(hands:, kitty:, ace: "D", trump: "S", discard: nil, rules: Rules.standard)
      round = Round.new(rules:, deal: deal_with(hands:, kitty:), dealer: 0)
      round = play(round, [ 1, bid("8") ], [ 2, Bidding::Pas.new ], [ 3, Bidding::Pas.new ], [ 0, Bidding::Pas.new ])
      play(round, [ 1, ChooseTrump.new(trump: Trump.parse(trump)) ], [ 1, CallAce.new(suit: ace) ], [ 1, Discard.new(cards: cards(discard || kitty)) ])
    end

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
