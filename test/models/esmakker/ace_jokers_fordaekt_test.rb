require "test_helper"

module Esmakker
  # Seam 1 for ticket 04: the called ace (owed by the esmakker the first
  # time its suit is led, Anders, 26 October 2026), the jokers with
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

    test "the esmakker must lay the called ace the first time its suit is led: no other card of the suit, no joker" do
      round = ready(hands: ACE_HANDS, kitty: ACE_KITTY)
      led = play(round, [ 1, card("2D") ])

      assert_equal %w[AD], led.view_for(2)[:play][:legal_moves]
      assert_equal :must_play_called_ace, led.apply(2, card("3D")).reason
      assert_equal :must_play_called_ace, led.apply(2, card("X1")).reason
      assert_equal :must_follow_suit, led.apply(2, card("2H")).reason
      assert_equal 2, play(led, [ 2, card("AD") ]).view_for(0)[:play][:esmakker]
    end

    test "leading before the ace's suit has been led, the esmakker may lead it only with the ace" do
      lead = esmakker_on_lead

      legal = lead.view_for(2)[:play][:legal_moves]
      assert_equal %w[AD X1 2H 2C].sort, (legal & %w[AD 3D X1 2H 2C]).sort, "anything but another diamond"
      assert_equal :must_play_called_ace, lead.apply(2, card("3D")).reason
      assert_equal [ "AD" ], play(lead, [ 2, card("AD") ]).view_for(3)[:play][:current_trick].map { |stik| stik[:card] }
    end

    test "a stik led with a joker is no lead in the ace's suit: the esmakker still owes the ace afterwards" do
      joker_won = play(esmakker_on_lead, [ 2, card("X1") ])
      joker_won = [ 3, 0, 1 ].reduce(joker_won) { |round, seat| play(round, [ seat, round.default_intent(seat) ]) }
      assert_equal 2, joker_won.to_act, "the led joker took the stik"
      assert_not_includes joker_won.view_for(2)[:play][:legal_moves], "3D"
    end

    test "once the ace has been played, as a discard too, the esmakker follows the suit by the normal rules" do
      round = play(ready(hands: ACE_HANDS, kitty: ACE_KITTY), [ 1, card("AS") ], [ 2, card("AD") ], [ 3, card("2S") ])
      round = play(round, [ 0, card(round.view_for(0)[:play][:legal_moves].first) ])
      assert_equal 1, round.to_act

      led = play(round, [ 1, card("2D") ])
      assert_equal %w[3D X1], led.view_for(2)[:play][:legal_moves].sort
    end

    test "nobody but the esmakker owes anything: a seat void in the suit may trump before the ace falls" do
      led = play(ready(hands: ACE_HANDS, kitty: ACE_KITTY), [ 1, card("2D") ], [ 2, card("AD") ])
      assert_equal ACE_HANDS[3].sort, led.view_for(3)[:play][:legal_moves].sort
      assert_equal [ nil, nil, nil ], [ 0, 1, 3 ].map { |seat| led.play.ace_owed(seat) }
    end

    test "a stored log from before the ace was owed still replays: the esmakker held it back, and the suit is then free" do
      led = play(ready(hands: ACE_HANDS, kitty: ACE_KITTY), [ 1, card("2D") ])
      assert_equal :must_play_called_ace, led.apply(2, card("3D")).reason, "never accepted now"

      old = Round.from_strings(rules: Rules.standard, deal: led.deal_string, dealer: 0, actions: "#{led.actions_string} 2:3D")
      assert_nil old.view_for(0)[:play][:esmakker], "she held the ace back and stays hidden"
      stik = [ 3, 0 ].reduce(old) { |round, seat| play(round, [ seat, round.default_intent(seat) ]) }
      assert_nil stik.play.ace_owed(2), "diamonds have been led: the normal rules from here"
      assert_equal 13, play_out(old).result.tricks_won.sum

      lead = esmakker_on_lead
      old_lead = Round.from_strings(rules: Rules.standard, deal: lead.deal_string, dealer: 1, actions: "#{lead.actions_string} 2:3D")
      assert_equal [ { seat: 2, card: "3D" } ], old_lead.view_for(0)[:play][:current_trick], "a lead in the suit without the ace"
    end

    test "a seat void in the ace's suit may trump the called ace after it falls, and the trump takes the stik" do
      round = play(ready(hands: ACE_HANDS, kitty: ACE_KITTY), [ 1, card("2D") ], [ 2, card("AD") ])

      assert_equal ACE_HANDS[3].sort, round.view_for(3)[:play][:legal_moves].sort, "void in diamonds: any card, spades included"
      taken = play(round, [ 3, card("2S") ], [ 0, card("4D") ])
      assert_equal 3, taken.view_for(1)[:play][:last_trick_winner]
    end

    test "a seat void in the suit that trumps before the ace falls takes the stik" do
      hands = { 1 => ACE_HANDS[1], 2 => ACE_HANDS[3], 3 => ACE_HANDS[2] }
      round = play(ready(hands:, kitty: ACE_KITTY), [ 1, card("2D") ])

      taken = play(round, [ 2, card("2S") ], [ 3, card("AD") ], [ 0, card("4D") ])
      assert_equal 2, taken.view_for(1)[:play][:last_trick_winner]
    end

    test "a selvmakker may hold the ace back when its suit is led" do
      hands = { 1 => %w[2C 2H 3H 4H 5H 6H 7H 8H 9H TH JH QH KH] }
      round = ready(hands:, kitty: %w[AD 4D 5D], ace: "D", trump: "H", discard: %w[2C 2H 3H])
      assert round.view_for(1)[:play][:selvmakker]

      # Seat 2 takes the first stik with the heart ace and leads diamonds.
      round = play(round, [ 1, card("KH") ], [ 2, card("AH") ], [ 3, card("5S") ], [ 0, card("3C") ])
      round = play(round, [ 2, card("3D") ], [ 3, card("6S") ], [ 0, card("2D") ])

      assert_equal %w[4D 5D AD], round.view_for(1)[:play][:legal_moves].sort
      assert_includes play(round, [ 1, card("4D") ]).view_for(1)[:hand], "AD", "she held the ace back"
    end

    test "at the stik's level: a led joker leaves no suit to follow; the ace is trumped like any card" do
      joker_led = Trick.lead(1).add(1, Card.parse("X1"))
      hand = cards(%w[AD 3D 2H])
      assert_nil joker_led.led_suit
      assert_equal hand, LegalMoves.for(hand:, trick: joker_led)
      set = joker_led.add(2, Card.parse("5D"))
      assert_equal hand, LegalMoves.for(hand:, trick: set), "the next playing card sets no suit either"

      led = Trick.lead(1).add(1, Card.parse("2D"))
      assert_equal cards(%w[AD 3D]), LegalMoves.for(hand:, trick: led)

      complete = led.add(2, Card.parse("AD")).add(3, Card.parse("2S")).add(0, Card.parse("4D"))
      assert_equal 3, complete.winner(Trump.parse("S"))
      assert_equal 2, complete.winner(Trump.trumfloes), "trumfløs: the ace is highest"
    end

    test "a led joker: every seat may play any card, whatever it holds" do
      round = ready(hands: FORDAEKT_HANDS, kitty: FORDAEKT_KITTY, discard: %w[2C 3C TC])
      led = play(round, [ 1, card("X3") ])
      assert_equal led.view_for(2)[:hand].sort, led.view_for(2)[:play][:legal_moves].sort
      followed = play(led, [ 2, card("AD") ])
      assert_equal followed.view_for(3)[:hand].sort, followed.view_for(3)[:play][:legal_moves].sort, "the ace sets no suit to follow"
      taken = play(followed, [ 3, card("7C") ], [ 0, card("5D") ])
      assert_equal 1, taken.view_for(0)[:play][:last_trick_winner]
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

    test "a melder void in the ace's suit after the kitty may lay one card fordækt, a joker too, before she leads" do
      round = ready(hands: FORDAEKT_HANDS, kitty: FORDAEKT_KITTY, discard: %w[2C 3C TC])

      offered = round.view_for(1)[:choices][:fordaekt]
      assert_equal round.view_for(1)[:hand].sort, offered.sort, "any card of her hand, the joker too"
      [ 0, 2, 3 ].each { |seat| assert_empty round.view_for(seat)[:choices][:fordaekt] }
      assert_equal :card_not_in_hand, round.apply(1, LayFordaekt.new(card: Card.parse("AD"))).reason
      assert_equal :not_your_turn, round.apply(2, LayFordaekt.new(card: Card.parse("AD"))).reason
      assert_kind_of PlayCard, round.default_intent(1), "a seat that acts without choosing never lays fordækt"

      laid = play(round, [ 1, LayFordaekt.new(card: Card.parse("9C")) ])
      assert_equal [ 12, 1 ], [ laid.view_for(1)[:hand].size, laid.to_act ]
      assert_empty laid.view_for(1)[:choices][:fordaekt], "only one card"
      assert_includes laid.view_for(1)[:play][:legal_moves], "9C", "she may lead it at once, or later"
      assert_equal({ seat: 1, card: "9C", waiting: true }, laid.view_for(1)[:play][:fordaekt])
      [ 0, 2, 3 ].each do |seat|
        view = laid.view_for(seat)
        assert_equal({ seat: 1, card: nil, waiting: true }, view[:play][:fordaekt])
        assert_equal 12, view[:card_counts][1]
        assert_not view.to_json.include?("\"9C\""), "seat #{seat} sees only the card's back"
      end
    end

    test "fordækt only when void in the ace's suit, with an esmakker, and before the first card" do
      holding = ready(hands: ACE_HANDS, kitty: ACE_KITTY)
      assert_empty holding.view_for(1)[:choices][:fordaekt]
      assert_equal :fordaekt_not_allowed, holding.apply(1, LayFordaekt.new(card: Card.parse("TC"))).reason

      # Holding all four aces, she calls one and lays it away: selvmakker,
      # with nobody to reach.
      all_aces = Round.new(rules: Rules.standard, deal: deal_with(hands: { 1 => %w[AC AD AH AS 2H 3H 4H 5H 6H 7H 8H 9H TH] }, kitty: %w[JH QH KH]), dealer: 0)
      all_aces = play(all_aces, [ 1, bid("8") ], [ 2, Bidding::Pas.new ], [ 3, Bidding::Pas.new ], [ 0, Bidding::Pas.new ],
                      [ 1, ChooseTrump.new(trump: Trump.parse("H")) ], [ 1, CallAce.new(suit: "D") ], [ 1, Discard.new(cards: cards(%w[AD 2H 3H])) ])
      assert all_aces.view_for(1)[:play][:selvmakker]
      assert_equal :fordaekt_not_allowed, all_aces.apply(1, LayFordaekt.new(card: Card.parse("AC"))).reason

      round = ready(hands: FORDAEKT_HANDS, kitty: FORDAEKT_KITTY, discard: %w[2C 3C TC])
      after = play(round, [ 1, card("AS") ], [ 2, card("2H") ], [ 3, card("2S") ], [ 0, card("JS") ])
      assert_equal 1, after.to_act
      assert_empty after.view_for(1)[:choices][:fordaekt]
      assert_equal :not_now, after.apply(1, LayFordaekt.new(card: Card.parse("9C"))).reason
      assert_equal :not_now, play(round, [ 1, LayFordaekt.new(card: Card.parse("9C")) ]).apply(1, LayFordaekt.new(card: Card.parse("AC"))).reason
    end

    test "a melder who is not forhånd may lay fordækt out of turn until the forhånd leads; nobody else sees the option" do
      hands = { 2 => FORDAEKT_HANDS[1].first(10) + %w[2C 3C TC], 1 => FORDAEKT_HANDS[2], 3 => FORDAEKT_HANDS[3] }
      round = Round.new(rules: Rules.standard, deal: deal_with(hands:, kitty: %w[JC 9C X3]), dealer: 0)
      round = play(round, [ 1, Bidding::Pas.new ], [ 2, bid("8") ], [ 3, Bidding::Pas.new ], [ 0, Bidding::Pas.new ],
                   [ 2, ChooseTrump.new(trump: Trump.parse("S")) ], [ 2, CallAce.new(suit: "D") ], [ 2, Discard.new(cards: cards(%w[2C 3C TC])) ])

      assert_equal [ :playing, 1, [ 1 ] ], [ round.phase, round.to_act, round.seats_to_act ]
      assert_equal [ 2 ], round.out_of_turn_seats, "for the bord: the melder may act out of turn"
      assert_equal round.view_for(2)[:hand].sort, round.view_for(2)[:choices][:fordaekt].sort, "offered while the forhånd has not led"
      [ 0, 1, 3 ].each do |seat|
        assert_empty round.view_for(seat)[:choices][:fordaekt]
        assert_equal 1, round.view_for(seat)[:to_act], "her option is no turn"
      end
      assert_nil round.default_intent(2)

      laid = play(round, [ 2, LayFordaekt.new(card: Card.parse("9C")) ])
      assert_equal [ 1, 12 ], [ laid.to_act, laid.view_for(2)[:hand].size ]
      assert_empty laid.out_of_turn_seats
      led = play(laid, [ 1, card("2H") ])
      assert_equal({ seat: 2, card: "9C", waiting: true }, led.view_for(2)[:play][:fordaekt])

      late = play(round, [ 1, card("2H") ])
      assert_empty late.view_for(2)[:choices][:fordaekt]
      assert_equal :not_now, late.apply(2, LayFordaekt.new(card: Card.parse("9C"))).reason, "too late once the forhånd has led"
      assert_empty late.out_of_turn_seats
    end

    test "asked out of turn, the first bot melder lays fordækt or not at random, and Svær lays its §6.4 card" do
      round = out_of_turn_round
      view = round.view_for(2)

      laid = (0...20).map { |seed| Bot.new(random: Random.new(seed)).decide_out_of_turn(view)&.intent }
      assert laid.any?(&:nil?), "sometimes it does not"
      assert laid.compact.any?, "sometimes it does"
      laid.compact.each { |intent| assert_includes view[:choices][:fordaekt], intent.card.to_s }
      assert_equal "lay_fordaekt", Bot.new(random: Random.new(laid.index { |intent| !intent.nil? })).decide_out_of_turn(view).thought[:decision]

      decision = Svaer.new(rules: Rules.standard).decide_out_of_turn(view)
      assert_equal [ LayFordaekt.new(card: Card.parse("JH")), "lay_fordaekt" ], [ decision.intent, decision.thought[:decision] ],
                   "the lowest card of its weakest side suit, never trump or a joker"
      assert play(round, [ 2, decision.intent ]).view_for(2)[:play][:fordaekt][:waiting]

      [ 0, 1, 3 ].each do |seat|
        assert_nil Bot.new(random: Random.new(0)).decide_out_of_turn(round.view_for(seat)), "seat #{seat} has nothing to do out of turn"
        assert_nil Svaer.new(rules: Rules.standard).decide_out_of_turn(round.view_for(seat))
      end
    end

    test "at halve the melder never takes the kitty: void in the ace's suit in her own hand, she may lay a card fordækt" do
      round = Round.new(rules: Rules.standard, deal: deal_with(hands: FORDAEKT_HANDS, kitty: FORDAEKT_KITTY), dealer: 0)
      round = play(round, [ 1, bid("8halve") ], [ 2, Bidding::Pas.new ], [ 3, Bidding::Pas.new ], [ 0, Bidding::Pas.new ])
      round = play(round, [ 1, CallAce.new(suit: "D") ], [ 2, ChooseTrump.new(trump: Trump.parse("S")) ], [ 2, Discard.new(cards: cards(%w[5C 6C 2H])) ])

      assert_equal [ :playing, 1 ], [ round.phase, round.to_act ]
      assert_equal FORDAEKT_HANDS[1].sort, round.view_for(1)[:choices][:fordaekt].sort
      laid = play(round, [ 1, LayFordaekt.new(card: Card.parse("9C")) ], [ 1, card("9C") ])
      assert_equal %w[AD], laid.view_for(2)[:play][:legal_moves], "at halve too, though everybody knows her, she owes the ace"
    end

    test "led, the fordækt card counts as the ace's suit: the others follow it, and its face is never shown to them" do
      round = play(ready(hands: FORDAEKT_HANDS, kitty: FORDAEKT_KITTY, discard: %w[2C 3C TC]), [ 1, LayFordaekt.new(card: Card.parse("9C")) ])

      led = play(round, [ 1, card("9C") ])
      assert_equal [ { seat: 1, card: "9C", fordaekt: true } ], led.view_for(1)[:play][:current_trick]
      [ 0, 2, 3 ].each { |seat| assert_equal [ { seat: 1, card: "fordaekt", fordaekt: true } ], led.view_for(seat)[:play][:current_trick] }
      assert_equal %w[AD], led.view_for(2)[:play][:legal_moves], "the fordækt card is the ace's suit led: the esmakker owes the ace"

      aced = play(led, [ 2, card("AD") ])
      assert_equal %w[4D X2], aced.view_for(3)[:play][:legal_moves], "seat 3 follows diamonds (or a joker)"
      assert_not aced.view_for(3).to_json.include?("\"9C\""), "still face down while the stik is open"

      taken = play(aced, [ 3, card("4D") ], [ 0, card("2D") ])
      assert_equal({ seat: 1, card: "9C", fordaekt: true }, taken.view_for(1)[:play][:last_trick].first, "the melder sees her own card")
      assert_equal({ seat: 1, card: "9C", waiting: false }, taken.view_for(1)[:play][:fordaekt])
      [ 0, 2, 3 ].each do |seat|
        view = taken.view_for(seat)[:play]
        assert_equal({ seat: 1, card: "fordaekt", fordaekt: true }, view[:last_trick].first, "never turned for seat #{seat}")
        assert_equal({ seat: 1, card: nil, waiting: false }, view[:fordaekt])
        assert_equal 2, view[:last_trick_winner]
      end
      done = play_out(taken)
      [ 0, 2, 3 ].each { |seat| assert_not done.view_for(seat).to_json.include?("\"9C\""), "not even after the runde (seat #{seat})" }
    end

    test "a joker laid fordækt is a card of the ace's suit: no led joker, followed in the suit, beaten by any real card of it" do
      round = play(ready(hands: FORDAEKT_HANDS, kitty: FORDAEKT_KITTY, discard: %w[2C 3C TC]), [ 1, LayFordaekt.new(card: Card.parse("X3")) ])
      assert_not_includes round.view_for(1)[:hand], "X3", "it lies on the table, not in her hand"
      led = play(round, [ 1, card("X3") ])
      [ 0, 2, 3 ].each { |seat| assert_equal "fordaekt", led.view_for(seat)[:play][:current_trick].first[:card] }
      assert_equal %w[AD], led.view_for(2)[:play][:legal_moves], "diamonds led, not a joker: the esmakker owes the ace"
      assert_equal %w[4D X2], play(led, [ 2, card("AD") ]).view_for(3)[:play][:legal_moves], "diamonds to follow, not a led joker"
      taken = play(led, [ 2, card("AD") ], [ 3, card("4D") ], [ 0, card("2D") ])
      assert_equal 2, taken.view_for(0)[:play][:last_trick_winner], "any real card of the suit beats it"
    end

    test "a fordækt card led takes the stik only when nobody follows the suit or trumps" do
      fordaekt = FordaektCard.new(card: Card.parse("X1"), suit: "D")
      alone = Trick.new(leader: 1, plays: [ [ 1, fordaekt ], [ 2, Card.parse("2H") ], [ 3, Card.parse("X2") ], [ 0, Card.parse("3C") ] ])
      assert_equal 1, alone.winner(Trump.parse("S"))
      trumped = Trick.new(leader: 1, plays: [ [ 1, fordaekt ], [ 2, Card.parse("2S") ], [ 3, Card.parse("X2") ], [ 0, Card.parse("3C") ] ])
      assert_equal 2, trumped.winner(Trump.parse("S"), joker_trumpable: false), "a fordækt joker is no led joker"
    end

    test "the fordækt card is the melder's card of the ace's suit wherever it is played, and ranks below every card of it" do
      fordaekt = FordaektCard.new(card: Card.parse("9C"), suit: "D")
      hand = [ fordaekt, *cards(%w[2H 3S]) ]

      diamonds = Trick.lead(2).add(2, Card.parse("3D"))
      assert_equal [ fordaekt ], LegalMoves.for(hand:, trick: diamonds), "she follows the ace's suit with it"
      clubs = Trick.lead(2).add(2, Card.parse("2C"))
      assert_equal hand, LegalMoves.for(hand:, trick: clubs), "void in clubs, it is a discard like any other"

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
      assert_raises(ArgumentError) { Round.from_strings(rules: Rules.standard, deal: done.deal_string, dealer: 0, actions: done.actions_string.sub("1:fordaekt-9C", "1:fordaekt-AD")) }
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

    # Seat 1 deals, so seat 2 is forhånd; seat 3 melder 8 in spades with
    # the diamond ace called. Seat 2, the esmakker, holds it and the 3D and
    # is to lead the first stik.
    def esmakker_on_lead
      round = Round.new(rules: Rules.standard, deal: deal_with(hands: { 2 => ACE_HANDS[2], 3 => ACE_HANDS[1] - %w[2D] + %w[2S] }, kitty: ACE_KITTY), dealer: 1)
      round = play(round, [ 2, Bidding::Pas.new ], [ 3, bid("8") ], [ 0, Bidding::Pas.new ], [ 1, Bidding::Pas.new ],
                   [ 3, ChooseTrump.new(trump: Trump.parse("S")) ], [ 3, CallAce.new(suit: "D") ])
      round = play(round, [ 3, Discard.new(cards: round.deal.hand(3).first(3)) ])
      assert_equal [ :playing, 2 ], [ round.phase, round.to_act ]
      round
    end

    # Seat 2 melder 8 in spades with the diamond ace called, void in
    # diamonds after the kitty; seat 1, the forhånd, is to lead.
    def out_of_turn_round
      hands = { 2 => FORDAEKT_HANDS[1].first(10) + %w[2C 3C TC], 1 => FORDAEKT_HANDS[2], 3 => FORDAEKT_HANDS[3] }
      round = Round.new(rules: Rules.standard, deal: deal_with(hands:, kitty: %w[JC 9C X3]), dealer: 0)
      play(round, [ 1, Bidding::Pas.new ], [ 2, bid("8") ], [ 3, Bidding::Pas.new ], [ 0, Bidding::Pas.new ],
           [ 2, ChooseTrump.new(trump: Trump.parse("S")) ], [ 2, CallAce.new(suit: "D") ], [ 2, Discard.new(cards: cards(%w[2C 3C TC])) ])
    end

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

    # Seat 1 bids 8 and the others pass; she names `trump`, calls `ace`,
    # lays three away and takes the kitty up, so that she then holds
    # `hands[1]` + `kitty` − `discard` (default: `hands[1]`). The deal
    # behind it: the kitty holds three of those cards (the kept cards of
    # `kitty` first, so a called ace there is still taken up from it), and
    # she is dealt the rest of them and the three she lays away.
    def ready(hands:, kitty:, ace: "D", trump: "S", discard: nil, rules: Rules.standard)
      discard ||= kitty
      after = hands[1] + kitty - discard
      taken = ((kitty & after) + (after - kitty).reverse).first(Deal::KITTY_SIZE)
      deal = deal_with(hands: hands.merge(1 => (after - taken) + discard), kitty: taken)
      round = Round.new(rules:, deal:, dealer: 0)
      round = play(round, [ 1, bid("8") ], [ 2, Bidding::Pas.new ], [ 3, Bidding::Pas.new ], [ 0, Bidding::Pas.new ])
      play(round, [ 1, ChooseTrump.new(trump: Trump.parse(trump)) ], [ 1, CallAce.new(suit: ace) ], [ 1, Discard.new(cards: cards(discard)) ])
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
