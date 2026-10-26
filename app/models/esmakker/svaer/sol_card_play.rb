module Esmakker
  class Svaer
    # Svær's stik at a sol-melding (strategy §6.7), the ace lowest: as a
    # sol player it leads singletons and safe suits, ducks under the stik's
    # highest card, takes its one allowed stik early with a dangerous high
    # card, and discards the high cards of its worst suits. As a modspiller
    # (or a sol player already væltet, or safe while others still play) it
    # leads middle cards from short suits, attacks the bordlægger's weak
    # suit, plays its highest card under a sol player's and low before one.
    module SolCardPlay
      include Cards
      extend Cards

      module_function

      def play(k, params)
        return defend(k, params) if defending?(k, params)

        cards = k.legal
        return lead(k, cards, params) if k.trick.empty?

        lead_card = k.trick.first.last
        return afkast(cards, params) if joker?(lead_card)

        led = suit(lead_card)
        following = cards.select { |card| !joker?(card) && suit(card) == led }
        return afkast(cards, params) if following.empty?

        top = k.trick.select { |_seat, card| !joker?(card) && suit(card) == led }.map { |_seat, card| sol_value(card) }.max
        under = following.select { |card| sol_value(card) < top }
        return [ under.max_by { |card| sol_value(card) }, "sol_under" ] if under.any?

        [ following.max_by { |card| sol_value(card) }, "sol_high" ]
      end

      def targets(k) = k.players.reject { |seat| seat == k.seat || k.vaeltet.include?(seat) }

      def defending?(k, params)
        return true if !k.players.include?(k.seat) || k.vaeltet.include?(k.seat)

        plain = k.hand.reject { |card| joker?(card) }
        (0..3).all? { |suit| Hand.suit_level(Hand.sol_values(plain, suit), params) == Hand::SAFE } && targets(k).any?
      end

      def levels(plain, params)
        (0..3).select { |suit| cards_in(plain, suit).any? }.to_h { |suit| [ suit, Hand.suit_level(Hand.sol_values(plain, suit), params) ] }
      end

      # Whether a card of the suit higher than `card` is still out.
      def unseen_above?(k, card)
        seen = Set.new(k.hand)
        k.tricks.each { |_leader, plays, _winner| plays.each { |_seat, played| seen << played } }
        k.trick.each { |_seat, played| seen << played }
        (0...52).any? { |other| !seen.include?(other) && suit(other) == suit(card) && sol_value(other) > sol_value(card) }
      end

      def lead(k, cards, params)
        plain = cards.reject { |card| joker?(card) }
        return [ cards.min, "any" ] if plain.empty?

        levels = levels(plain, params)
        if k.most_stik - k.tricks_won[k.seat] > 0
          levels.keys.sort.select { |suit| levels[suit] == Hand::DANGER }.each do |suit|
            high = cards_in(plain, suit).max_by { |card| sol_value(card) }
            safe_left = levels.any? { |other, level| other != suit && level == Hand::SAFE }
            return [ high, "sol_take" ] if sol_value(high) >= params.sol_take && !unseen_above?(k, high) && safe_left
          end
        end
        singles = levels.keys.sort.select { |suit| cards_in(plain, suit).size == 1 }.map { |suit| cards_in(plain, suit).first }
        singles = singles.select { |card| sol_value(card) <= params.sol_singleton_lead }
        return [ singles.min_by { |card| [ sol_value(card), card ] }, "sol_lead" ] if singles.any?

        safe = plain.select { |card| levels[suit(card)] == Hand::SAFE }
        return [ safe.min_by { |card| [ sol_value(card), card ] }, "sol_lead" ] if safe.any?

        [ plain.min_by { |card| [ sol_value(card), card ] }, "sol_lead" ]
      end

      def afkast(cards, params)
        plain = cards.reject { |card| joker?(card) }
        jokers = cards.select { |card| joker?(card) }
        return [ cards.min, "sol_afkast" ] if plain.empty?

        levels = levels(plain, params)
        return [ jokers.first, "sol_afkast" ] if jokers.any? && levels.values.all? { |level| level == Hand::SAFE }

        suit = levels.keys.min_by { |s| [ levels[s], cards_in(plain, s).size, -cards_in(plain, s).map { |card| sol_value(card) }.max, s ] }
        [ cards_in(plain, suit).max_by { |card| sol_value(card) }, "sol_afkast" ]
      end

      # Who has shown void where, who led which suit (in order), and who
      # laid a very low card under a high one (a suit she is clearly safe in).
      def voids(k)
        void = Array.new(4) { [ false ] * 4 }
        led_by = []
        clearly_safe = Array.new(4) { [ false ] * 4 }
        [ *k.tricks.map { |_leader, plays, _winner| plays }, k.trick ].each do |plays|
          next if plays.empty? || joker?(plays.first.last)

          led = suit(plays.first.last)
          led_by << [ plays.first.first, led ]
          top = plays.select { |_seat, card| !joker?(card) && suit(card) == led }.map { |_seat, card| sol_value(card) }.max
          plays.drop(1).each do |seat, card|
            next if joker?(card)

            void[seat][led] = true if suit(card) != led
            clearly_safe[seat][led] = true if suit(card) == led && sol_value(card) <= 3 && top >= 10
          end
        end
        [ void, led_by, clearly_safe ]
      end

      def middle_card(cards, params) = cards.min_by { |card| [ (sol_value(card) - params.sol_middle).abs, sol_value(card), card ] }

      def defend(k, params)
        cards = k.legal
        plain = cards.reject { |card| joker?(card) }
        return [ cards.min, "any" ] if plain.empty?

        k.trick.empty? ? defend_lead(k, plain, params) : defend_follow(k, plain, params)
      end

      def defend_lead(k, plain, params)
        targets = targets(k)
        void, led_by, clearly_safe = voids(k)
        if !k.open_hand.nil? && targets.include?(k.melder)
          best = nil
          plain.map { |card| suit(card) }.uniq.sort.each do |suit|
            values = Hand.sol_values(k.open_hand, suit)
            next if values.empty?

            weak = values.each_with_index.map { |value, index| value - (2 * index + 1) }.max
            best = [ suit, weak ] if best.nil? || weak > best.last
          end
          return [ cards_in(plain, best.first).min_by { |card| sol_value(card) }, "sol_defend_lead" ] if best
        end
        suits = plain.map { |card| suit(card) }.uniq.sort
        if k.tricks.empty?
          suit = suits.min_by { |s| [ cards_in(plain, s).size, s ] }
          mine = cards_in(plain, suit)
          return [ mine.size == 1 ? mine.first : middle_card(mine, params), "sol_defend_lead" ]
        end
        options = prefer(suits) { |s| targets.none? { |target| void[target][s] } }
        options = prefer(options) { |s| led_by.none? { |seat, led| targets.include?(seat) && s == led } }
        options = prefer(options) { |s| targets.none? { |target| clearly_safe[target][s] } }
        chosen = led_by.find { |seat, led| !k.players.include?(seat) && options.include?(led) }&.last
        chosen ||= options.min_by { |s| [ cards_in(plain, s).size, s ] }
        mine = cards_in(plain, chosen)
        [ mine.size >= 3 ? middle_card(mine, params) : mine.min_by { |card| sol_value(card) }, "sol_defend_lead" ]
      end

      def prefer(suits, &keep)
        kept = suits.select(&keep)
        kept.empty? ? suits : kept
      end

      def defend_follow(k, plain, params)
        targets = targets(k)
        void, = voids(k)
        lead_seat, lead_card = k.trick.first
        led = joker?(lead_card) ? -1 : suit(lead_card)
        following = led >= 0 ? plain.select { |card| suit(card) == led } : []
        if following.empty?
          suits = prefer(plain.map { |card| suit(card) }.uniq.sort) { |s| targets.none? { |target| void[target][s] } }
          suit = suits.min_by { |s| [ cards_in(plain, s).size, -cards_in(plain, s).map { |card| sol_value(card) }.max, s ] }
          return [ cards_in(plain, suit).max_by { |card| sol_value(card) }, "sol_defend_afkast" ]
        end
        top_seat, top_card = k.trick.select { |_seat, card| !joker?(card) && suit(card) == led }.max_by { |_seat, card| sol_value(card) }
        top = sol_value(top_card)
        if targets.include?(lead_seat) && sol_value(lead_card) <= params.sol_cover && top_seat == lead_seat
          above = following.select { |card| sol_value(card) > top }
          return [ above.min_by { |card| sol_value(card) }, "sol_cover" ] if above.any?
        end
        if targets.include?(top_seat)
          under = following.select { |card| sol_value(card) < top }
          return [ under.max_by { |card| sol_value(card) }, "sol_defend_under" ] if under.any?
        end
        [ following.min_by { |card| sol_value(card) }, "sol_defend_low" ]
      end
    end
  end
end
