module Hjerterfri
  # A computer player with a rule-based strategy at one of three levels,
  # Let ⊂ Mellem ⊂ Svær (docs/bots/hjerterfri-strategy.md; decided with
  # Anders in ticket 20). It reads a seat's view (Round#view_for) and
  # returns card codes, or a moon choice. It only ever picks from the legal
  # moves, and it never waits: the client paces what humans see.
  #
  # Between moves that are almost as good, it draws lots with the injected
  # `random:` (spec §3), so a seeded bot is deterministic.
  class Bot
    LEVELS = %i[let mellem svaer].freeze
    PASS_SIZE = 3
    QUEEN = Knowledge::QUEEN
    HIGH_SPADES = Knowledge::HIGH_SPADES
    JACK_OF_DIAMONDS = Card::JACK_OF_DIAMONDS
    QUEEN_GUARDS = 3 # Q♠ is passed with fewer than this many other spades
    LOW_SPADE = Card::RANKS.index("J") # "low spades": jack and below
    LOW_HEART = Card::RANKS.index("6") # "low hearts": 2–6, kept in the pass
    TOP_HEARTS = %w[AH KH QH].map { |code| Card.parse(code) }.freeze
    MINOR_SUITS = %w[D C].freeze # voids are made in diamonds first, then clubs
    HIGH = Card::RANKS.index("T") # [valgt] "a high card": ten and up

    attr_reader :level

    def initialize(level: :mellem, random: Random.new)
      raise ArgumentError, "unknown bot level: #{level.inspect}" unless LEVELS.include?(level)

      @level = level
      @random = random
    end

    # The three card codes to pass, from the seat's view (or just its hand).
    def choose_pass(view)
      view = { hand: view } if view.is_a?(Array)
      hand = view[:hand].map { |code| Card.parse(code) }
      picks =
        if level == :let then let_pass(hand)
        elsif level == :svaer && moon_hand?(hand) then moon_pass(hand)
        else mellem_pass(hand)
        end
      (picks + highest_first(hand)).uniq.first(PASS_SIZE).map(&:to_s)
    end

    # A card code from the view's legal moves. Svær also reads the spil
    # totals and the end score.
    def choose_play(view, totals: nil, end_score: nil)
      known = Knowledge.new(view, level:, totals:, end_score:)
      legal = known.legal
      return legal.first.to_s if legal.size == 1

      card =
        if known.leading? then lead(known)
        elsif legal.first.suit == known.led_suit then follow(known)
        else discard(known)
        end
      vary(card, known).to_s
    end

    # The moon choice under shooter's choice, given the totals before this
    # runde. Both options move the shooter 26 against everyone else; 26 to
    # the others also brings the end score closer. So a shooter who leads
    # (or shares the lead) hurries the end; anyone else takes −26.
    def choose_moon(seat:, totals:)
      totals[seat] <= totals.min ? "add_to_others" : "subtract_from_self"
    end

    private

    def mellem? = level != :let
    def svaer? = level == :svaer

    # ── Passing ─────────────────────────────────────────────────────────

    # Spec §4: Q♠ with too few spades under it, A♠/K♠ without Q♠, then the
    # highest hearts, then the highest cards.
    def let_pass(hand)
      picks = []
      picks << QUEEN if hand.include?(QUEEN) && lower_spades(hand) < QUEEN_GUARDS
      picks.concat(highest_first(hand & HIGH_SPADES)) unless hand.include?(QUEEN)
      picks.concat(highest_first(hand.select(&:heart?)))
      keep = hand.include?(QUEEN) && !picks.include?(QUEEN) ? [ QUEEN ] : []
      picks + highest_first(hand - keep)
    end

    # Spec §5: Q♠ away, A♠/K♠ away, a void in diamonds or clubs, the top
    # hearts, then the highest cards of the longest suits. Low spades and
    # low hearts stay.
    def mellem_pass(hand)
      picks = []
      picks << QUEEN if hand.include?(QUEEN) && other_spades(hand) < QUEEN_GUARDS
      if !hand.include?(QUEEN) && low_spades(hand) < QUEEN_GUARDS
        picks.concat(highest_first(hand & HIGH_SPADES))
      end
      void = MINOR_SUITS.map { |suit| hand.select { |card| card.suit == suit } }
                        .find { |suit_cards| suit_cards.any? && suit_cards.size <= PASS_SIZE - picks.size }
      picks.concat(highest_first(void)) if void
      picks.concat(highest_first(hand & TOP_HEARTS))
      kept = hand.select { |card| (card.suit == "S" && card.rank_value <= LOW_SPADE) || (card.heart? && card.rank_value <= LOW_HEART) }
      kept << QUEEN if hand.include?(QUEEN) && !picks.include?(QUEEN)
      rest = (hand - kept).sort_by { |card| [ -card.rank_value, -suit_length(hand, card.suit), Card::SUITS.index(card.suit) ] }
      picks + rest
    end

    # Spec §6: with a moon hand, keep hearts and high cards; give away the
    # lowest cards of the weakest suits.
    def moon_pass(hand)
      others = hand.reject { |card| card.heart? || card == QUEEN }
      others.sort_by { |card| [ suit_strength(hand, card.suit), card.rank_value, Card::SUITS.index(card.suit) ] }
    end

    # Spec §6 [valgt]: A♥ K♥ Q♥ with 6+ hearts, or A♥ K♥ Q♥ and a 6-card
    # suit headed by its ace. Q♠ in the hand needs three other spades.
    def moon_hand?(hand)
      return false unless (TOP_HEARTS - hand).empty?
      return false if hand.include?(QUEEN) && other_spades(hand) < QUEEN_GUARDS

      hearts = hand.count(&:heart?)
      long_with_ace = %w[C D S].any? { |suit| suit_length(hand, suit) >= 6 && hand.include?(Card.new(rank: "A", suit:)) }
      hearts >= 6 || long_with_ace
    end

    # ── Leading ─────────────────────────────────────────────────────────

    def lead(known)
      legal = known.legal
      if svaer?
        return highest_first(legal).first if shooting_moon?(known)

        late = late_lead(known)
        return late if late

        safe_high = safe_high_lead(known)
        return safe_high if safe_high

        queen_hunt = known.queen_holder && known.queen_holder != known.me && lowest(legal.select { |card| card.suit == "S" && card.rank_value < QUEEN.rank_value })
        return queen_hunt if queen_hunt
      end

      if mellem?
        void_plan = void_plan_lead(known)
        return void_plan if void_plan

        if known.queen_out? && (known.hand & [ QUEEN, *HIGH_SPADES ]).empty?
          spade = lowest(legal.select { |card| card.suit == "S" && card.rank_value < QUEEN.rank_value })
          return spade if spade
        end
      end

      let_lead(known)
    end

    # The lowest card, preferring non-penalty cards, never a dangerous one
    # (Q♠, or A♠/K♠ while Q♠ is out), and not a high card in a suit where
    # someone may drop points on it, while another will do.
    def let_lead(known)
      legal = known.legal
      safe = legal.reject { |card| dangerous?(card, known) }
      safe = legal if safe.empty?
      safe.min_by { |card| [ card.penalty? ? 1 : 0, high_and_risky?(card, known) ? 1 : 0, card.rank_value, card.suit ] }
    end

    def high_and_risky?(card, known) = card.rank_value >= HIGH && known.risky?(card.suit)

    # Spec §5: in the first stik, run the shortest diamond or club suit from
    # the top to make a void, while hearts are unbroken and nobody has shown
    # out of it.
    def void_plan_lead(known)
      return nil if known.hand.size < 10 || known.hearts_broken?

      suits = MINOR_SUITS.map { |suit| known.legal.select { |card| card.suit == suit } }
                         .select { |suit_cards| suit_cards.any? && suit_cards.size <= PASS_SIZE && !known.risky?(suit_cards.first.suit) }
      shortest = suits.min_by(&:size)
      shortest && highest_first(shortest).first
    end

    # Spec §6: late in the runde, lead an exit card (the highest one, to keep
    # the low cards for the end).
    def late_lead(known)
      return nil unless known.late?

      exits = known.legal.select { |card| known.exit?(card) && !dangerous?(card, known) }
      highest_first(exits).first
    end

    # Spec §6: in the middle of the runde, cash a suit's top card when
    # nobody is known void in it and the stik is safe (Knowledge#safe?).
    # Not hearts, and not spades while Q♠ is out.
    def safe_high_lead(known)
      return nil if known.late? || known.hand.size > 11

      tops = known.legal.select do |card|
        !card.heart? && !(card.suit == "S" && known.queen_out?) && known.top?(card) &&
          !known.anyone_else_void?(card.suit) && known.safe?(card.suit)
      end
      highest_first(tops).first
    end

    # ── Following suit ──────────────────────────────────────────────────

    def follow(known)
      legal = known.legal
      winning = known.winning_card
      winners = legal.select { |card| card.rank_value > winning.rank_value }
      losers = legal - winners

      return highest_first(legal).first if svaer? && shooting_moon?(known) && winners.any?

      blocker = block_moon(known, winners)
      return blocker if blocker

      jack = take_jack(known, winners)
      return jack if jack

      if mellem? && known.led_suit == "D" && known.jack_rule? && losers.any? && jack_out?(known)
        return lowest(losers)
      end

      if mellem? && winners.any? && clean_and_safe?(known)
        shed = highest_first(winners.reject { |card| card == QUEEN || (card == JACK_OF_DIAMONDS && known.jack_rule?) }).first
        return shed if shed
      end

      return highest_first(losers.reject { |card| avoid_jack?(card, known) }).first || highest_first(losers).first if losers.any?

      others = legal - [ QUEEN ]
      others = legal if others.empty?
      known.last_to_play? ? highest_first(others).first : lowest(others)
    end

    # Spec §5: a stik with nothing to lose: the bot plays last (or, in
    # spades, Q♠ can no longer come) and the stik holds no penalty cards.
    def clean_and_safe?(known)
      return false if known.trick_points.positive?
      return true if known.last_to_play?

      known.led_suit == "S" && (known.queen_played? || queen_holder_has_played?(known))
    end

    def queen_holder_has_played?(known)
      holder = known.queen_holder
      holder && known.trick.any? { |play| play[:seat] == holder }
    end

    # Spec §5: under a moon threat, take a stik holding penalty cards with
    # the lowest winning card, even Q♠ (13 is less than 26). Svær skips it
    # when those points would bring it to the end score.
    def block_moon(known, winners)
      threat = known.moon_threat
      return nil unless threat && winners.any? && known.trick_points.positive?
      return nil if known.over_with?(known.me, known.trick_points + 13)

      lowest(winners)
    end

    # Spec §5, J♦ −10: take a clean stik holding J♦ with the lowest winning diamond.
    def take_jack(known, winners)
      return nil unless known.jack_rule? && known.trick_cards.include?(JACK_OF_DIAMONDS) && known.trick_points.zero?

      lowest(winners.select { |card| card.suit == "D" })
    end

    def jack_out?(known) = !known.played.include?(JACK_OF_DIAMONDS) && !known.hand.include?(JACK_OF_DIAMONDS)

    # Don't throw J♦ under another's diamond while it can be lost.
    def avoid_jack?(card, known) = card == JACK_OF_DIAMONDS && known.jack_rule?

    # ── Discarding (void in the led suit) ───────────────────────────────

    def discard(known)
      legal = known.legal
      return lowest(legal.reject(&:penalty?)) || lowest(legal) if svaer? && shooting_moon?(known)

      winner = known.winning_play[:seat]
      unless feed?(known, winner)
        clean = legal.reject(&:penalty?)
        return highest_first(clean).first if clean.any?
      end

      return QUEEN if legal.include?(QUEEN)

      hearts = legal.select(&:heart?)
      return highest_first(hearts).first if hearts.any? && !mellem?
      return highest_first(legal).first unless mellem?

      high_spades = legal & HIGH_SPADES
      return highest_first(high_spades).first if high_spades.any? && known.queen_out?

      hearts = legal.select(&:heart?)
      return highest_first(hearts).first if hearts.any?

      shed_from_short_suit(known)
    end

    # Whether to give penalty cards to the seat winning the stik. Mellem
    # does not feed a would-be moon shooter. Svær gives points where they
    # hurt it least: never to a seat they would push over the end score
    # while Svær is not lowest (that would end the spil with Svær losing).
    def feed?(known, winner)
      return false if known.moon_threat == winner
      return true unless known.scores?

      points = known.legal.include?(QUEEN) ? QUEEN.points : 1
      !(known.over_with?(winner, points) && !known.lowest?)
    end

    # Spec §5: the highest card of the shortest suit, to make a void. Under
    # a moon threat, keep the two highest cards for the last stik; Svær keeps
    # low cards in at least two suits.
    def shed_from_short_suit(known)
      legal = known.legal
      keep = known.moon_threat ? highest_first(legal).first(2) : []
      candidates = legal - keep
      candidates = legal if candidates.empty?
      candidates = keep_two_low_suits(candidates, known) if svaer?
      candidates.max_by { |card| [ -suit_length(known.hand, card.suit), card.rank_value ] }
    end

    def keep_two_low_suits(candidates, known)
      low_suits = known.hand.select { |card| card.rank_value <= Card::RANKS.index("7") }.map(&:suit).uniq
      return candidates if low_suits.size > 2

      spared = candidates.reject { |card| card.rank_value <= Card::RANKS.index("7") && known.hand.count { |other| other.suit == card.suit && other.rank_value <= Card::RANKS.index("7") } == 1 }
      spared.any? ? spared : candidates
    end

    # ── The moon (Svær) ─────────────────────────────────────────────────

    # Svær goes for the moon only with a moon hand after the pass, and stops
    # as soon as another seat has taken a penalty card. Not when the points
    # it may have to eat could end the spil against it.
    def shooting_moon?(known)
      return false unless svaer?
      return false if known.penalty_taken.each_index.any? { |seat| seat != known.me && known.penalty_taken[seat].positive? }
      return false if known.scores? && known.totals[known.me] + 26 >= known.end_score && !known.lowest?

      moon_hand?(known.hand_after_pass)
    end

    # ── Variation (spec §3) ─────────────────────────────────────────────

    # Draw lots between the chosen card and its near-equals: Let and Mellem
    # take a neighbour in rank, Svær only cards made equivalent by the count.
    # Both must play the same role: win or lose the stik alike, carry the
    # same points, and not be Q♠, A♠/K♠ or J♦.
    def vary(card, known)
      peers = known.legal.select do |other|
        other != card && other.suit == card.suit && same_role?(other, card, known) &&
          (svaer? ? known.equivalent?(card, other) : (other.rank_value - card.rank_value).abs == 1)
      end
      return card if peers.empty?

      [ card, *peers ].sample(random: @random)
    end

    def same_role?(other, card, known)
      special = [ QUEEN, *HIGH_SPADES, JACK_OF_DIAMONDS ]
      return false if special.include?(other) || special.include?(card)
      return false unless other.points == card.points
      return true if known.leading? || known.led_suit != card.suit

      winning = known.winning_card.rank_value
      (other.rank_value > winning) == (card.rank_value > winning)
    end

    # ── Helpers ─────────────────────────────────────────────────────────

    # Q♠, or A♠/K♠ while Q♠ is out: they can be made to take 13 points.
    def dangerous?(card, known) = card == QUEEN || (HIGH_SPADES.include?(card) && known.queen_out?)

    def lower_spades(hand) = hand.count { |card| card.suit == "S" && card.rank_value < QUEEN.rank_value }
    def other_spades(hand) = hand.count { |card| card.suit == "S" && card != QUEEN }
    def low_spades(hand) = hand.count { |card| card.suit == "S" && card.rank_value <= LOW_SPADE }
    def suit_length(hand, suit) = hand.count { |card| card.suit == suit }
    def suit_strength(hand, suit) = hand.select { |card| card.suit == suit }.sum(&:rank_value)

    def lowest(cards) = cards.min_by { |card| [ card.rank_value, Card::SUITS.index(card.suit) ] }
    def highest_first(cards) = cards.sort_by { |card| [ -card.rank_value, Card::SUITS.index(card.suit) ] }
  end
end
