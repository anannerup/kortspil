module Hjerterfri
  # A computer player with a simple rule-based strategy. Stateless and
  # deterministic: it reads a seat's view (Round#view_for) or a hand and
  # returns card codes, or a moon choice. It never waits: the client paces what humans see.
  #
  # The view holds no history beyond the current and last stik, so the bot
  # cannot track which cards are gone. It treats Q♠ as still out unless it
  # holds it.
  class Bot
    PASS_SIZE = 3
    # Q♠ is kept when at least this many lower spades can be played under it.
    QUEEN_GUARDS = 4
    QUEEN_OF_SPADES = Card.parse("QS")
    HIGH_SPADES = [ Card.parse("KS"), Card.parse("AS") ].freeze

    # A card code from the view's legal moves.
    def choose_play(view)
      legal = view[:legal_moves].map { |code| Card.parse(code) }
      trick = view[:current_trick].map { |play| Card.parse(play[:card]) }
      return legal.first.to_s if legal.size == 1

      card =
        if trick.empty? then lead(legal)
        elsif legal.first.suit == trick.first.suit then follow(legal, trick)
        else discard(legal)
        end
      card.to_s
    end

    # The three card codes to pass, from a hand of card codes.
    def choose_pass(hand)
      cards = hand.map { |code| Card.parse(code) }
      keep_queen = cards.include?(QUEEN_OF_SPADES) && queen_guarded?(cards)
      picks = []
      picks << QUEEN_OF_SPADES if cards.include?(QUEEN_OF_SPADES) && !keep_queen
      picks.concat(highest_first(cards & HIGH_SPADES)) unless cards.include?(QUEEN_OF_SPADES)
      picks.concat(highest_first(cards.select(&:heart?)))
      picks.concat(highest_first(cards.reject { |card| keep_queen && card == QUEEN_OF_SPADES }))
      picks.uniq.first(PASS_SIZE).map(&:to_s)
    end

    # The moon choice under shooter's choice, given the totals before this
    # runde. Both options move the shooter 26 against everyone else; 26 to
    # the others also brings the end score closer. So a shooter who leads
    # (or shares the lead) hurries the end; anyone else takes −26.
    # Provisional, like the rest of the strategy (ticket 20).
    def choose_moon(seat:, totals:)
      totals[seat] <= totals.min ? "add_to_others" : "subtract_from_self"
    end

    private

    # The lowest card, preferring non-hearts, and never Q♠ or a spade above
    # it while another card will do (leading A♠/K♠ invites the Q♠ onto it).
    def lead(legal)
      safe = legal.reject { |card| card == QUEEN_OF_SPADES || HIGH_SPADES.include?(card) }
      safe = legal if safe.empty?
      safe.min_by { |card| [ card.heart? ? 1 : 0, card.rank_value, card.suit ] }
    end

    # Duck under the stik with the highest card that still loses. If every
    # card wins: the last seat takes it with its highest card (shedding a
    # high card it would otherwise have to win with later); earlier seats
    # play their lowest and hope someone goes over. Q♠ is avoided while
    # another card will do, as it would win its own 13 points.
    def follow(legal, trick)
      winning = trick.select { |card| card.suit == trick.first.suit }.max_by(&:rank_value)
      losers = legal.select { |card| card.rank_value < winning.rank_value }
      return losers.max_by(&:rank_value) if losers.any?

      others = legal - [ QUEEN_OF_SPADES ]
      others = legal if others.empty?
      trick.size == Deal::SEAT_COUNT - 1 ? others.max_by(&:rank_value) : others.min_by(&:rank_value)
    end

    # Void in the led suit: dump Q♠, then the highest heart, then the highest card.
    def discard(legal)
      return QUEEN_OF_SPADES if legal.include?(QUEEN_OF_SPADES)

      hearts = legal.select(&:heart?)
      return highest_first(hearts).first if hearts.any?

      highest_first(legal).first
    end

    def queen_guarded?(cards)
      cards.count { |card| card.suit == "S" && card.rank_value < QUEEN_OF_SPADES.rank_value } >= QUEEN_GUARDS
    end

    def highest_first(cards) = cards.sort_by { |card| [ -card.rank_value, Card::SUITS.index(card.suit) ] }
  end
end
