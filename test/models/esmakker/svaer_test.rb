require "test_helper"

module Esmakker
  # Svær (docs/bots/esmakker-strategy.md §6) through a Round and on
  # hand-made knowledge: its meldinger for sample hands, the discard under
  # both values of the bord's rule "Afkast", trump drawn with good trumps
  # and makker played in early with weak ones, never a bank, and only legal
  # moves over many runder, alone and with the first bot.
  #
  # Seat 0 deals, so seat 1 is forhånd. Cards in Svær's integers: suit × 13
  # + rank (C D H S; 2 … A), via Svaer::Cards.int.
  class SvaerTest < ActiveSupport::TestCase
    STRONG = %w[AS KS QS JS 9S 8S AH KH AD QD KC QC X1].freeze
    MEDIUM = %w[AS KS QS 7S 5S AH 4H 3H AD 5D 4C 3C 2C].freeze
    WEAK = %w[2C 3C 4C 5C 2D 3D 4D 5D 2H 3H 4H 6S 7S].freeze

    test "it judges its hand per trump: its own stik, makker 3½, katten nothing" do
      params = Svaer::Params.standard
      values = Svaer::Hand.estimates(ints(STRONG), params)

      assert_equal Rational(31, 2), values[2 + 1] # spades: 6 trump + AK hjerter 2 + AD 1,5 + KD in the called clubs 1,5 + joker 1, makker 3½
      assert_equal 13, Svaer::Hand.nmax(values.max, params)
      assert_equal 10, Svaer::Hand.nmax(Svaer::Hand.estimates(ints(MEDIUM), params).max, params)
      assert_nil Svaer::Hand.nmax(Svaer::Hand.estimates(ints(WEAK), params).max, params)
    end

    test "the meldingsrunde: the lowest melding worth the most, pas when weak or bid over" do
      strong = decide(round_with(1 => STRONG), 1)
      assert_equal bid("8vip"), strong.intent
      assert_equal({ decision: "bid", reason: "bid_vip", melding: "8vip" }, strong.thought.slice(:decision, :reason, :melding))
      assert_equal({ self: 12, makker: 3.5 }, strong.thought[:expect][:stik])

      medium = decide(round_with(1 => MEDIUM), 1)
      assert_equal [ bid("8"), "bid_lowest" ], [ medium.intent, medium.thought[:reason] ]
      assert_equal 3, medium.thought[:expect][:points]
      weak = decide(round_with(1 => WEAK), 1)
      assert_equal [ Bidding::Pas.new, "pas_weak" ], [ weak.intent, weak.thought[:reason] ]

      over = play(round_with(2 => MEDIUM), [ 1, bid("11") ])
      too_high = decide(over, 2)
      assert_equal [ Bidding::Pas.new, "pas_too_high" ], [ too_high.intent, too_high.thought[:reason] ]
    end

    test "Afkast = Renonce: it discards from the suit it wants to be void in" do
      k = knowledge(hand: ints(%w[5S 6S AH 4H 3D 7D 9D]), trump: 3, trick: [ [ 0, int("KC") ] ])

      card, reason = Svaer::CardPlay.follow(k, Svaer::Memory.new(k, Svaer::Params.standard))

      assert_equal [ int("3D"), "afkast_renonce" ], [ card, reason ]
    end

    test "Afkast = Spil den her: it discards from the suit it wants led, keeping the honour" do
      k = knowledge(hand: ints(%w[5S 6S AH 4H 3D 7D 9D]), trump: 3, trick: [ [ 0, int("KC") ] ], rules: Rules.new(afkast: "spil_den_her"))

      card, reason = Svaer::CardPlay.follow(k, Svaer::Memory.new(k, Svaer::Params.standard))

      assert_equal [ int("4H"), "afkast_spil" ], [ card, reason ]
    end

    test "it reads makker's discard by the bord's rule when it leads" do
      # Clubs are trump; the melder (seat 1) discarded a ruder on a club lead.
      stik = [ 3, [ [ 3, int("2C") ], [ 0, int("5C") ], [ 1, int("3D") ], [ 2, int("4C") ] ], 3 ]
      hand = ints(%w[6D 8D 9H TH 2S])
      renonce = knowledge(seat: 3, melder: 1, esmakker: 3, called: 2, hand:, tricks: [ stik ], trump: 0)
      spil = knowledge(seat: 3, melder: 1, esmakker: 3, called: 2, hand:, tricks: [ stik ], trump: 0, rules: Rules.new(afkast: "spil_den_her"))
      params = Svaer::Params.standard

      # "Spil den her": lead it to her. "Renonce": she wants to ruff ruder,
      # but she has no trump left to ruff with, so not that.
      assert_equal [ int("6D"), "signal_suit" ], Svaer::CardPlay.lead(spil, Svaer::Memory.new(spil, params), params)
      assert_not_equal "signal_suit", Svaer::CardPlay.lead(renonce, Svaer::Memory.new(renonce, params), params).last
    end

    test "as melder with good trumps it draws trump from the top; with weak ones it plays makker in first" do
      good = knowledge(seat: 1, melder: 1, called: 2, hand: ints(%w[AS KS QS 9S 7S 4H 3D 5D 7D 2C 3C 4C 5C]), trump: 3)
      weak = knowledge(seat: 1, melder: 1, called: 2, hand: ints(%w[9S 7S 5S 4S 3S 4H AD 5D 7D 2C 3C 4C 5C]), trump: 3)
      params = Svaer::Params.standard

      assert_equal [ int("AS"), "draw_trump" ], Svaer::CardPlay.lead(good, Svaer::Memory.new(good, params), params)
      assert_equal [ int("4H"), "makker_in" ], Svaer::CardPlay.lead(weak, Svaer::Memory.new(weak, params), params)
    end

    test "as esmakker it lays the called ace the first time its suit is led" do
      k = knowledge(seat: 2, esmakker: 2, called: 2, hand: ints(%w[AH 4H 3D]), trump: 3, trick: [ [ 1, int("5H") ] ])

      assert_equal [ int("AH"), "lay_ace" ], Svaer::CardPlay.follow(k, Svaer::Memory.new(k, Svaer::Params.standard))
    end

    test "it never banks, and every move it makes over many runder is legal, alone and with the first bot" do
      40.times do |index|
        rules = Rules.new(afkast: Rules::AFKAST[index % 2], joker_trumpable: index % 3 == 0)
        svaer = index.even? ? [ 0, 1, 2, 3 ] : [ index % 4 ]
        round = Round.new(rules:, deal: Deal.shuffled(shuffler: Random.new(index)), dealer: index % 4)
        first = Bot.new(random: Random.new(index))
        until round.complete? || round.redeal?
          if round.banking?
            Seats::ALL.each { |seat| assert_nil Svaer.new(rules:).decide(round.view_for(seat)) }
            round = round.apply(round.play.melder, CloseBankWindow.new).round
            next
          end
          seat = round.to_act
          decision = (svaer.include?(seat) ? Svaer.new(rules:) : first).decide(round.view_for(seat))
          result = round.apply(seat, decision.intent)
          assert result.accepted?, "seat #{seat} #{decision.intent.inspect} at #{round.phase}: #{result.reason}"
          round = result.round
        end
      end
    end

    test "it never banks: in the bank window it has nothing to do" do
      round = round_with(1 => STRONG)
      round = play(round, [ 1, bid("8vip") ], [ 2, Bidding::Pas.new ], [ 3, Bidding::Pas.new ], [ 0, Bidding::Pas.new ])
      round = play(round, [ 1, CallAce.new(suit: "C") ], [ 1, TurnCard.new ], [ 1, AcceptTrump.new ])
      round = play(round, [ 1, Discard.new(cards: round.play.hand(1).first(3)) ])

      assert round.banking?
      Seats::ALL.each { |seat| assert_nil Svaer.new(rules: Rules.standard).decide(round.view_for(seat)) }
    end

    test "it lays away from its own 13 cards, never the kitty's" do
      round = play(round_with(1 => MEDIUM), [ 1, bid("8") ], [ 2, Bidding::Pas.new ], [ 3, Bidding::Pas.new ], [ 0, Bidding::Pas.new ])
      round = play(round, [ 1, ChooseTrump.new(trump: Trump.parse("S")) ], [ 1, CallAce.new(suit: "C") ])
      decision = decide(round, 1)
      kitty = round.deal.kitty

      assert_equal 3, decision.intent.cards.size
      assert_empty decision.intent.cards & kitty
    end

    test "EsmakkerSpil gives Svær at level svaer and the first bot at let and mellem" do
      spil = Struct.new(:engine_round, :engine_rules).new(round_with(1 => WEAK), Rules.standard)

      assert_equal "pas_weak", EsmakkerSpil.bot_decision(spil, 1, level: :svaer, random: Random.new(0)).thought[:reason]
      %i[let mellem].each do |level|
        assert_equal "fixed_melding", EsmakkerSpil.bot_decision(spil, 1, level:, random: Random.new(0)).thought[:reason]
      end
    end

    private

    def int(code) = Svaer::Cards.int(code)
    def ints(codes) = codes.map { |code| int(code) }.sort
    def bid(code) = Bidding::Bid.new(melding: Melding.parse(code))
    def decide(round, seat) = Svaer.new(rules: round.rules).decide(round.view_for(seat))

    def round_with(hands)
      placed = hands.values.flatten.map { |code| Card.parse(code) }
      rest = Card.deck - placed
      filled = (0..3).map do |seat|
        own = hands.fetch(seat, []).map { |code| Card.parse(code) }
        own + rest.shift(Deal::HAND_SIZE - own.size)
      end
      Round.new(rules: Rules.standard, deal: Deal.new(hands: filled, kitty: rest.shift(3)), dealer: 0)
    end

    def play(round, *steps)
      steps.reduce(round) do |before, (seat, intent)|
        result = before.apply(seat, intent)
        assert result.accepted?, "seat #{seat} #{intent.inspect}: #{result.reason}"
        result.round
      end
    end

    # Knowledge of a stik melding being played, seat 0 a modspiller to
    # melder 1 by default; the legal cards are the whole hand unless a
    # suit was led that the hand holds.
    def knowledge(seat: 0, melder: 1, esmakker: nil, called: 0, hand:, trump:, trick: [], tricks: [], rules: Rules.standard)
      led = trick.empty? || trick.first.last >= 52 ? nil : trick.first.last / 13
      following = led && hand.select { |card| card / 13 == led && card < 52 }
      legal = following.present? ? following : hand
      Svaer::Knowledge.new(
        seat:, phase: "playing", hand:, rules:, melding: Svaer::Cards.melding_int("9"), bids: [], can_selv: false, can_med: false,
        can_pas: false, trumps: [], aces: [], can_turn: false, can_accept: false, kind: "stik", melder:, trump:, called:,
        esmakker:, selvmakker: false, turned: [], vip_card: nil, banks: 0, discard_size: 0, discarded: [], fordaekt_card: nil,
        fordaekt_waiting: false, fordaekt_options: [], tricks:, trick:, tricks_won: [ 0 ] * 4, legal:, players: [],
        most_stik: nil, vaeltet: [], open_hand: nil, kitty_cards: []
      )
    end
  end
end
