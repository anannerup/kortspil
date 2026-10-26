module Esmakker
  class Svaer
    # Svær between the meldingsrunde and the first stik (strategy §6.4):
    # trump, the called ace, vip's turning, the cards laid away (at a
    # sol-melding the exchange, §6.7), and what it expects of the runde.
    module Declaring
      include Cards
      extend Cards

      module_function

      # What Svær expects of the runde ("Vis kort"): its own stik (taken
      # plus its estimate of the rest), the melder's makker's 2, its
      # partner's seat, and for the melder the risk-weighted points.
      def expect(k, params, trump = k.trump, called = k.called)
        expect = Svaer.no_expect(k.melding)
        if k.kind == "sol"
          expect[:stik][:self] = k.tricks_won[k.seat]
          return expect
        end
        own = trump.nil? ? Hand.own_estimates(k.hand, params, called).max : Hand.own_stik(k.hand, trump, called, params)
        mine = k.tricks_won[k.seat] + own
        expect[:stik][:self] = num(mine)
        expect[:makker] = CardPlay.guessed_partner(k, params)
        return expect unless k.seat == k.melder

        makker = k.selvmakker ? Rational(0) : params.makker_stik
        expect[:stik][:makker] = num(makker)
        unless trump.nil?
          taken = !k.esmakker.nil? && k.esmakker != k.seat ? k.tricks_won[k.esmakker] : 0
          expect[:points] = num(Hand.stik_value(k.melding, mine + makker + taken, trump, k.rules.points, params, k.vip_card, k.banks))
        end
        expect
      end

      def choose_trump(k, params)
        values = Hand.estimates(k.hand, params, k.called)
        best = nil
        k.trumps.each { |trump| best = trump if trump != NT && (best.nil? || values[trump] > values[best]) }
        if k.trumps.include?(NT) && k.melding
          number = number(k.melding)
          if values[NT] >= number + params.nt_margin && values[NT] >= values[best] - params.nt_close
            return [ [ :trump, NT ], Svaer.thought("choose_trump", "trumfloes", nil, expect(k, params, NT, k.called)) ]
          end
        end
        [ [ :trump, best ], Svaer.thought("choose_trump", "best_trump", nil, expect(k, params, best, k.called)) ]
      end

      def call_ace(k, params)
        trump = k.trump.nil? ? Hand.best_suit(Hand.estimates(k.hand, params)) : k.trump
        suit = Hand.call_choice(k.hand, trump, k.aces)
        [ [ :ace, suit ], Svaer.thought("call_ace", "call_shortest", nil, expect(k, params, k.trump, suit)) ]
      end

      # At vip: take the turned card when its trump gives S ≥ N + margin.
      def turn(k, params)
        if k.can_accept && k.turned.any?
          card = k.turned.last
          trump = joker?(card) ? NT : suit(card)
          value = Hand.own_stik(k.hand, trump, k.called, params) + params.makker_stik
          if value >= number(k.melding) + params.vip_accept_margin || !k.can_turn
            return [ [ :accept ], Svaer.thought("accept_trump", "vip_accept", nil, expect(k, params, trump)) ]
          end
        end
        [ [ :turn ], Svaer.thought("turn_card", "vip_turn", nil, expect(k, params)) ]
      end

      # The seat's own cards when it lays away: never the kitty's (REGLER
      # §2.0: the melder lays three away before she takes the kitty up; at
      # a sol-melding each seat likewise). While the engine still hands the
      # kitty over first, its cards are left out here.
      def own_cards(k) = k.hand - k.kitty_cards

      def discard(k, params)
        own = own_cards(k)
        if k.kind == "sol"
          cards = sol_discard(own, k.discard_size, params)
          return [ [ :discard, cards.sort ], Svaer.thought("discard", "sol_discard", nil, expect(k, params)) ]
        end
        cards, reason = stik_discard(own, k.trump, k.called)
        rest = own - cards
        expect = expect(k, params)
        expect[:stik][:self] = num(k.tricks_won[k.seat] + Hand.own_stik(rest, k.trump, k.called, params))
        [ [ :discard, cards.sort ], Svaer.thought("discard", reason, nil, expect) ]
      end

      # Three cards to lay away from the 16 (§6.4 "Katten"): never trump,
      # jokers, aces or the called suit's king; with 4+ trump the shortest
      # side suit emptied; otherwise the lowest of the weakest side suit.
      def stik_discard(hand, trump, called)
        protected = ->(card) { joker?(card) || suit(card) == trump || rank(card) == ACE || (suit(card) == called && rank(card) == KING) }
        chosen = []
        reason = "discard_low"
        trumps = trump == NT ? 0 : hand.count { |card| suit(card) == trump }
        if trump != NT && trumps >= 4
          side = (0..3).select { |suit| ![ trump, called ].include?(suit) && cards_in(hand, suit).any? { |card| !protected.(card) } }
          if side.any?
            suit = side.min_by { |s| [ cards_in(hand, s).size, s ] }
            cards_in(hand, suit).each { |card| chosen << card if !protected.(card) && chosen.size < 3 }
            reason = "discard_void"
          end
        end
        while chosen.size < 3
          rest = hand - chosen
          options = (0..3).select { |suit| suit != trump && suit != called && cards_in(rest, suit).any? { |card| !protected.(card) } }
          options = (0..3).select { |suit| suit != trump && cards_in(rest, suit).any? { |card| !protected.(card) } } if options.empty?
          break if options.empty?

          suit = options.min_by { |s| [ Hand.quick_tricks(ranks_in(rest, s)), cards_in(rest, s).size, s ] }
          chosen << cards_in(rest, suit).find { |card| !protected.(card) }
        end
        while chosen.size < 3
          rest = hand - chosen
          chosen << rest.min_by { |card| [ joker?(card) ? 1 : 0, suit(card) == trump ? 1 : 0, rank(card) == ACE ? 1 : 0, rank(card), card ] }
        end
        [ chosen, reason ]
      end

      # §6.7 "Katten ved sol": the highest cards of the worst, shortest suits.
      def sol_discard(hand, size, params)
        chosen = []
        while chosen.size < size
          rest = hand - chosen
          plain = rest.reject { |card| joker?(card) }
          if plain.empty?
            chosen << rest.min
            next
          end
          suit = plain.map { |card| suit(card) }.uniq.sort.min_by do |s|
            values = Hand.sol_values(rest, s)
            [ Hand.suit_level(values, params), values.size, -values.last, s ]
          end
          chosen << cards_in(rest, suit).max_by { |card| sol_value(card) }
        end
        chosen
      end
    end
  end
end
