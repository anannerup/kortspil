module Esmakker
  class Svaer
    # Svær's stik at a stik melding (strategy §6.5, §6.6): fordækt, the
    # lead as melder (draw trump with good trumps, play makker in early
    # with weak ones), as esmakker (trump when forhånd, show the ace)
    # and as modspiller (cash aces and jokers, never trump as forhånd,
    # leading the first stik), following (second hand low, third hand only as high as it
    # takes, the called ace laid at once, ruff what goes to the other side)
    # and the discard by the bord's rule "Afkast". A sol-melding goes to
    # SolCardPlay.
    module CardPlay
      include Cards
      extend Cards

      module_function

      def play(k, params)
        if k.kind == "sol"
          card, reason = SolCardPlay.play(k, params)
          return [ [ :play, card ], Svaer.thought("play", reason, nil, Declaring.expect(k, params)) ]
        end
        memory = Memory.new(k, params)
        if k.fordaekt_options.any?
          card = fordaekt_card(k)
          return [ [ :fordaekt, card ], Svaer.thought("lay_fordaekt", "fordaekt", nil, Declaring.expect(k, params)) ] if card
        end
        card, reason = k.trick.empty? ? lead(k, memory, params) : follow(k, memory)
        [ [ :play, card ], Svaer.thought("play", reason, nil, Declaring.expect(k, params)) ]
      end

      # --- partners ---

      # The seat Svær knows is its partner this runde, or nil.
      def partner(k)
        return nil unless k.kind == "stik"
        return (!k.esmakker.nil? && k.esmakker != k.seat ? k.esmakker : nil) if k.seat == k.melder
        return k.melder if k.esmakker == k.seat
        return nil if k.selvmakker || k.esmakker.nil?

        (0..3).find { |seat| ![ k.seat, k.melder, k.esmakker ].include?(seat) }
      end

      # The seat with the highest weight (clockwise from Svær on a tie).
      def makker_guess(memory)
        weights = memory.weights
        return nil if weights.nil? || weights.empty?

        k = memory.k
        best = nil
        [ 1, 2, 3 ].each do |offset|
          seat = (k.seat + offset) % 4
          best = seat if weights.key?(seat) && weights[seat].positive? && (best.nil? || weights[seat] > weights[best])
        end
        best
      end

      # expect.makker: the seat Svær takes for its partner.
      def guessed_partner(k, params)
        return nil unless k.kind == "stik"
        return nil if k.called.nil? && k.seat != k.melder

        memory = Memory.new(k, params)
        known = partner(k)
        return known if !known.nil? || k.selvmakker
        return k.melder if k.esmakker == k.seat

        guess = makker_guess(memory)
        return guess if k.seat == k.melder || guess.nil?

        (0..3).find { |seat| ![ k.seat, k.melder, guess ].include?(seat) }
      end

      def opponents(k)
        mate = partner(k)
        (0..3).reject { |seat| seat == k.seat || seat == mate }
      end

      def opps_may_trump?(k, memory)
        return false unless memory.trumps_out?

        opponents(k).any? { |seat| !memory.void[seat][memory.trump] }
      end

      # --- cards ---

      # §6.4: the lowest card of the weakest side suit, never trump or joker.
      def fordaekt_card(k)
        options = (0..3).select { |suit| suit != k.trump && cards_in(k.hand, suit).any? }
        return nil if options.empty?

        suit = options.min_by { |s| [ Hand.quick_tricks(ranks_in(k.hand, s)), cards_in(k.hand, s).size, s ] }
        card = cards_in(k.hand, suit).first
        k.fordaekt_options.include?(card) ? card : nil
      end

      def fordaekt?(k, card) = k.fordaekt_waiting && k.seat == k.melder && card == k.fordaekt_card

      def trumps_in(k, memory, cards)
        trump = memory.trump
        return [] if trump.nil? || trump == NT

        cards.select { |card| suit(card) == trump && !fordaekt?(k, card) }
      end

      def side_cards(k, memory, cards)
        trump = memory.trump
        cards.select { |card| !joker?(card) && (trump.nil? || trump == NT || suit(card) != trump) && !fordaekt?(k, card) }
      end

      # Whether the seat leads the runde's first stik: it is "i forhånd"
      # (§6.6; the forhånd leads the first stik at every melding, REGLER
      # §2.0).
      def first_lead?(k) = k.tricks.empty?

      def lowest_card(cards)
        plain = cards.reject { |card| joker?(card) }
        plain.any? ? plain.min_by { |card| [ rank(card), card ] } : cards.min
      end

      def highest_trump(k, memory, cards) = trumps_in(k, memory, cards).max_by { |card| rank(card) }

      # The highest trump when it is the highest out, else the lowest.
      def trump_lead(k, memory, cards)
        trumps = trumps_in(k, memory, cards)
        return nil if trumps.empty?

        top = trumps.max_by { |card| rank(card) }
        memory.sure?(top) ? top : trumps.min_by { |card| rank(card) }
      end

      # §6.6: the highest of a top sequence, the highest of a weak suit,
      # otherwise the lowest.
      def top_sequence_lead(cards)
        ordered = cards.sort_by { |card| -rank(card) }
        return ordered.first if ordered.size >= 2 && rank(ordered[0]) - rank(ordered[1]) == 1 && rank(ordered[0]) >= JACK
        return ordered.first if rank(ordered.first) < QUEEN

        ordered.last
      end

      # §6.6: not from a bare king at the top or a tenace (E D, K B).
      def bad_lead_suit?(ranks)
        return true if ranks.include?(ACE) && ranks.include?(QUEEN) && !ranks.include?(KING)

        ranks.include?(KING) && !ranks.include?(ACE) && !ranks.include?(QUEEN)
      end

      # --- leads ---

      def lead(k, memory, params)
        return melder_lead(k, memory, params) if k.seat == k.melder
        return esmakker_lead(k, memory) if k.esmakker == k.seat

        defender_lead(k, memory)
      end

      # A sure winner in a side suit: the highest, in the longest such suit.
      def cash(k, memory, cards, opps_trump)
        winners = side_cards(k, memory, cards).select { |card| memory.sure?(card) }
        winners = winners.reject { |card| opponents(k).any? { |seat| memory.void[seat][suit(card)] } } if opps_trump
        return nil if winners.empty?

        suit = winners.map { |card| suit(card) }.uniq.min_by { |s| [ -cards_in(cards, s).size, s ] }
        winners.select { |card| suit(card) == suit }.max_by { |card| rank(card) }
      end

      def joker_lead(k, cards, opps_trump)
        jokers = cards.select { |card| joker?(card) }
        jokers.any? && (!k.rules.joker_trumpable || !opps_trump) ? jokers.first : nil
      end

      # The suit the partner discarded last: by "Renonce" (while the
      # partner may still trump it) or by "Spil den her".
      def signal_lead(k, memory, cards)
        mate = partner(k)
        return nil if mate.nil? || memory.discards[mate].empty?

        suit = memory.discards[mate].last
        mine = side_cards(k, memory, cards).select { |card| suit(card) == suit }
        return nil if mine.empty?
        if k.rules.afkast == "renonce"
          trump = memory.trump
          return nil if trump.nil? || trump == NT || memory.void[mate][trump] || !memory.trumps_out?
        end
        mine.first
      end

      def long_lead(k, memory, cards, shortest: false, avoid_bad: false)
        side = side_cards(k, memory, cards)
        return nil if side.empty?

        suits = side.map { |card| suit(card) }.uniq.sort
        if k.rules.afkast == "renonce" && opps_may_trump?(k, memory)
          safe = suits.reject { |s| opponents(k).any? { |seat| memory.discards[seat].include?(s) } }
          suits = safe if safe.any?
        end
        if avoid_bad
          good = suits.reject { |s| bad_lead_suit?(ranks_in(side, s)) }
          suits = good if good.any?
        end
        suit = suits.min_by { |s| [ shortest ? cards_in(side, s).size : -cards_in(side, s).size, s ] }
        top_sequence_lead(cards_in(side, suit))
      end

      def initial_trumps(k, memory)
        mine = Set.new(k.hand)
        k.tricks.each { |_leader, plays, _winner| plays.each { |seat, card| mine << card if seat == k.seat && card != FACE_DOWN } }
        k.trick.each { |seat, card| mine << card if seat == k.seat && card != FACE_DOWN }
        trump = memory.trump
        trumps = mine.select { |card| !trump.nil? && trump != NT && suit(card) == trump }
        side_aces = mine.select { |card| !joker?(card) && rank(card) == ACE && suit(card) != trump }
        [ trumps, side_aces ]
      end

      # §6.5: with good trumps draw trump, then makker in; with weak ones
      # makker in first. Then the partner's signal, sure winners, a joker,
      # the long suit, trump last.
      def melder_lead(k, memory, params)
        cards = k.legal
        trumps, side_aces = initial_trumps(k, memory)
        honours = trumps.count { |card| [ ACE, KING, QUEEN ].include?(rank(card)) }
        good = trumps.size >= params.good_trump_count && honours >= params.good_trump_honours
        ruff_plan = trumps.size >= 5 && side_aces.empty?
        opps_trump = opps_may_trump?(k, memory)
        led_trump = k.tricks.any? { |leader, plays, _winner| leader == k.seat && plays.any? && plays.first.last != FACE_DOWN && suit(plays.first.last) == memory.trump }
        draw = lambda do
          next nil if !opps_trump || (ruff_plan && led_trump)

          top = highest_trump(k, memory, cards)
          top && memory.sure?(top) ? top : nil
        end
        makker_in = lambda do
          next nil if memory.ace_fallen || k.selvmakker || k.called.nil?
          next k.fordaekt_card if k.fordaekt_waiting && cards.include?(k.fordaekt_card)

          cards.select { |card| suit(card) == k.called && !fordaekt?(k, card) }.min_by { |card| rank(card) }
        end
        steps = [ [ draw, "draw_trump" ], [ makker_in, "makker_in" ] ]
        steps.reverse! unless good
        steps += [ [ -> { signal_lead(k, memory, cards) }, "signal_suit" ],
                   [ -> { cash(k, memory, cards, opps_trump) }, "cash" ],
                   [ -> { joker_lead(k, cards, opps_trump) }, "joker_lead" ],
                   [ -> { long_lead(k, memory, cards, shortest: ruff_plan) }, "long_suit" ],
                   [ -> { highest_trump(k, memory, cards) }, "trump_last" ] ]
        steps.each do |step, reason|
          card = step.call
          return [ card, reason ] unless card.nil?
        end
        [ lowest_card(cards), "any" ]
      end

      # §6.6 as esmakker: trump when it is forhånd and leads the first
      # stik (Anders), the ace while it has not fallen, trump while the modspillere may have some, the
      # partner's signal, the melder's suit, its own long suit.
      def esmakker_lead(k, memory)
        cards = k.legal
        opps_trump = opps_may_trump?(k, memory)
        if first_lead?(k)
          card = trump_lead(k, memory, cards)
          return [ card, "makker_trump" ] if card
        end
        return [ ace(k.called), "show_ace" ] if cards.include?(ace(k.called))
        if opps_trump
          card = trump_lead(k, memory, cards)
          return [ card, "makker_trump" ] if card
        end
        [ [ -> { signal_lead(k, memory, cards) }, "signal_suit" ],
          [ -> { return_lead(k, memory, cards, k.melder) }, "return_suit" ],
          [ -> { long_lead(k, memory, cards) }, "long_suit" ],
          [ -> { highest_trump(k, memory, cards) }, "trump_last" ] ].each do |step, reason|
          card = step.call
          return [ card, reason ] unless card.nil?
        end
        [ lowest_card(cards), "any" ]
      end

      # §6.6: the suit `seat` led last (not trump, not the called suit):
      # the lowest from 4+, the highest from 2.
      def return_lead(k, memory, cards, seat)
        memory.led[seat].reverse_each do |suit|
          next if suit == memory.trump || (seat == k.melder && suit == k.called)

          mine = side_cards(k, memory, cards).select { |card| suit(card) == suit }
          next if mine.empty?

          return mine.size == 2 ? mine.max_by { |card| rank(card) } : mine.min_by { |card| rank(card) }
        end
        nil
      end

      # §6.6 as modspiller: cash sure winners and jokers at once (as
      # forhånd, leading the first stik, whatever the risk of a ruff: it may
      # not get the lead again; Anders), the top trump two for one (never
      # as forhånd), the partner's signal, its suit, the long suit.
      def defender_lead(k, memory)
        cards = k.legal
        opps_trump = opps_may_trump?(k, memory)
        first = first_lead?(k)
        card = cash(k, memory, cards, first ? false : opps_trump)
        return [ card, "cash" ] if card

        card = joker_lead(k, cards, opps_trump)
        return [ card, "joker_lead" ] if card

        unless first
          top = trumps_in(k, memory, cards).max_by { |c| rank(c) }
          return [ top, "top_trump" ] if top && memory.sure?(top) && memory.unseen.count { |c| suit(c) == memory.trump } >= 2
        end
        card = signal_lead(k, memory, cards)
        return [ card, "signal_suit" ] if card

        mate = partner(k)
        card = mate && return_lead(k, memory, cards, mate)
        return [ card, "return_suit" ] if card

        card = long_lead(k, memory, cards, avoid_bad: true)
        return [ card, "long_suit" ] if card

        trumps = trumps_in(k, memory, cards)
        return [ trumps.min_by { |c| rank(c) }, "trump_last" ] if trumps.any?

        [ lowest_card(cards), "any" ]
      end

      # --- following ---

      def follow(k, memory)
        cards = k.legal
        trick = k.trick
        leader_card = trick.first.last
        led = memory.joker_card?(leader_card) ? -1 : memory.suit_of(leader_card)
        winner = memory.winner(trick)
        mate = partner(k)
        return [ ace(k.called), "lay_ace" ] if k.esmakker == k.seat && !k.called.nil? && led == k.called && cards.include?(ace(k.called))

        following = cards.select { |card| (!joker?(card) && led >= 0 && suit(card) == led) || (led == k.called && fordaekt?(k, card)) }
        return follow_suit(k, memory, following, winner, mate) if following.any?

        if led.negative?
          if k.rules.joker_trumpable && (mate.nil? || trick.first.first != mate)
            card = lowest_winning_trump(k, memory, cards, trick)
            return [ card, "ruff" ] if card
          end
          return afkast(k, memory, cards)
        end
        if winner != k.seat && (mate.nil? || winner != mate)
          card = lowest_winning_trump(k, memory, cards, trick)
          return [ card, "ruff" ] if card
        end
        afkast(k, memory, cards)
      end

      def follow_suit(k, memory, following, winner, mate)
        trick = k.trick
        key = ->(card) { [ fordaekt?(k, card) ? -1 : rank(card), card ] }
        low = following.min_by(&key)
        return [ low, "makker_wins" ] if !mate.nil? && winner == mate && (trick.size == 3 || mate_sure?(memory, trick))

        beating = following.select { |card| memory.winner(trick + [ [ k.seat, fordaekt?(k, card) ? FACE_DOWN : card ] ]) == k.seat }.sort_by(&key)
        if trick.size == 1
          seq = following.select { |card| !fordaekt?(k, card) && memory.sure?(card) }
          lowest = seq.min_by { |card| rank(card) }
          return [ lowest, "follow_sequence" ] if seq.size >= 2 && beating.include?(lowest)

          return [ low, "follow_low" ]
        end
        return [ low, "follow_low" ] if beating.empty?

        first = beating.first
        if k.seat == k.melder && trick.size < 3 && !memory.sure?(first)
          sure = beating.select { |card| memory.sure?(card) }
          taken = k.tricks_won[k.seat] + (mate.nil? ? 0 : k.tricks_won[mate])
          winners = k.hand.count { |card| memory.sure?(card) }
          return [ sure.first, "no_finesse" ] if sure.any? && taken + winners < number(k.melding)
        end
        [ first, "follow_win" ]
      end

      # The partner's card in the stik wins for sure: no card out beats it.
      def mate_sure?(memory, trick)
        taker = memory.winner(trick)
        card = trick.find { |seat, _card| seat == taker }.last
        return false if card == FACE_DOWN
        return true if joker?(card)

        suit = suit(card)
        return false if rank(card) <= memory.highest_out(suit)

        trump = memory.trump
        !(!trump.nil? && trump != NT && suit != trump && memory.trumps_out?)
      end

      def lowest_winning_trump(k, memory, cards, trick)
        trumps_in(k, memory, cards).sort_by { |card| rank(card) }.find { |card| memory.winner(trick + [ [ k.seat, card ] ]) == k.seat }
      end

      # §6.6: a discard that signals by the bord's rule "Afkast"; never a
      # king left bare.
      def afkast(k, memory, cards)
        side = side_cards(k, memory, cards)
        if side.empty?
          plain = cards.reject { |card| joker?(card) || fordaekt?(k, card) }
          return [ plain.any? ? plain.min_by { |card| [ rank(card), card ] } : cards.min, "afkast" ]
        end
        suits = side.map { |card| suit(card) }.uniq.sort
        guarded = suits.reject { |s| king_guard?(ranks_in(k.hand, s)) }
        suits = guarded if guarded.any?
        trump = memory.trump
        if k.rules.afkast == "spil_den_her"
          wanted = suits.select do |s|
            ranks = ranks_in(side, s)
            ranks.size >= 2 && (ranks.include?(ACE) || (ranks.include?(KING) && ranks.include?(QUEEN)))
          end
          if wanted.any?
            suit = wanted.min_by { |s| [ -Hand.quick_tricks(ranks_in(side, s)), s ] }
            return [ cards_in(side, suit).min_by { |card| rank(card) }, "afkast_spil" ]
          end
        elsif !trump.nil? && trump != NT && trumps_in(k, memory, k.hand).any?
          empty = suits.reject { |s| cards_in(side, s).any? { |card| memory.sure?(card) } }
          if empty.any?
            suit = empty.min_by { |s| [ cards_in(side, s).size, s ] }
            return [ cards_in(side, suit).min_by { |card| rank(card) }, "afkast_renonce" ]
          end
        end
        suit = suits.min_by { |s| [ Hand.quick_tricks(ranks_in(side, s)), cards_in(side, s).size, s ] }
        [ cards_in(side, suit).min_by { |card| rank(card) }, "afkast" ]
      end

      # A suit where a discard would bare or throw the king (§6.6).
      def king_guard?(ranks) = ranks.include?(KING) && !ranks.include?(ACE) && ranks.size <= 2
    end
  end
end
