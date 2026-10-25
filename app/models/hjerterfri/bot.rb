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
    LOW_CARD = Card::RANKS.index("7") # "low cards": seven and below
    SVAER_QUEEN_GUARDS = 5 # [valgt] Svær passes Q♠ unless it has this many other spades
    SAFE_SHED = 0.3 # [valgt] Svær takes a stik early when the seats after it can be expected to drop less
    HEART_LIABILITY = 0.6 # [valgt] Svær's discard: what being a heart adds to a card's chance to win
    SHORT_LIABILITY = 0.2 # [valgt] Svær's discard: what each card of its suit takes off

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
      picks << QUEEN if hand.include?(QUEEN) && other_spades(hand) < (svaer? ? SVAER_QUEEN_GUARDS : QUEEN_GUARDS)
      if !hand.include?(QUEEN) && low_spades(hand) < QUEEN_GUARDS
        picks.concat(highest_first(hand & HIGH_SPADES))
      end
      void = MINOR_SUITS.map { |suit| hand.select { |card| card.suit == suit } }
                        .find { |suit_cards| suit_cards.any? && suit_cards.size <= PASS_SIZE - picks.size }
      picks.concat(highest_first(void)) if void
      picks.concat(highest_first(hand & TOP_HEARTS))
      kept = hand.select { |card| (card.suit == "S" && card.rank_value <= LOW_SPADE) || (card.heart? && card.rank_value <= LOW_HEART) }
      kept << QUEEN if hand.include?(QUEEN) && !picks.include?(QUEEN)
      picks + pass_rest(hand - kept, hand)
    end

    # The highest cards from the longest suits; Svær first from the suits
    # with the fewest low cards (they are the ones that win stik later).
    def pass_rest(cards, hand)
      unless svaer?
        return cards.sort_by { |card| [ -card.rank_value, -suit_length(hand, card.suit), Card::SUITS.index(card.suit) ] }
      end

      cards.sort_by do |card|
        [ low_cards(hand, card.suit), -card.rank_value, -suit_length(hand, card.suit), Card::SUITS.index(card.suit) ]
      end
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

        # Press with the highest spade under Q♠; low spades stay as the bot's own guard (Anders, 2026-10-25).
        queen_hunt = known.queen_holder && known.queen_holder != known.me && highest_first(legal.select { |card| card.suit == "S" && card.rank_value < QUEEN.rank_value }).first
        return queen_hunt if queen_hunt
      end

      if mellem?
        void_plan = void_plan_lead(known)
        return void_plan if void_plan

        if known.queen_out? && (known.hand & [ QUEEN, *HIGH_SPADES ]).empty?
          spade = highest_first(legal.select { |card| card.suit == "S" && card.rank_value < QUEEN.rank_value }).first
          return spade if spade
        end
      end

      svaer? ? cost_lead(known) : let_lead(known)
    end

    # The lowest card, preferring non-penalty cards, never a dangerous one
    # (Q♠, or A♠/K♠ while Q♠ is out), and not a high card in a suit where
    # someone may drop points on it, while another will do.
    def let_lead(known)
      safe_leads(known).min_by { |card| [ card.penalty? ? 1 : 0, known.risky?(card.suit) ? 1 : 0, card.rank_value, card.suit ] }
    end

    # Svær: the lead with the fewest expected penalty points
    # (Knowledge#lead_cost), the lower card on a tie. A card that loses for
    # sure costs nothing, so exit cards come first, all through the runde.
    def cost_lead(known)
      safe_leads(known).min_by { |card| [ known.lead_cost(card), card.rank_value ] }
    end

    def safe_leads(known)
      safe = known.legal.reject { |card| dangerous?(card, known) }
      safe.empty? ? known.legal : safe
    end

    # Spec §5: in the first stik, run the shortest diamond or club suit from
    # the top to make a void, while hearts are unbroken and nobody has shown
    # out of it.
    def void_plan_lead(known)
      return nil if known.hand.size < 10 || known.hearts_broken?

      suits = MINOR_SUITS.map { |suit| known.legal.select { |card| card.suit == suit } }
                         .select { |suit_cards| suit_cards.any? && suit_cards.size <= PASS_SIZE && !known.risky?(suit_cards.first.suit) }
      shortest = suits.min_by(&:size)
      card = shortest && highest_first(shortest).first
      # Svær with J♦ −10 counted doesn't run J♦ while it can be lost.
      return nil if card == JACK_OF_DIAMONDS && known.jack_count? && !known.top?(card)

      card
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

      jack = known.jack_count? ? count_jack(known, winners) : take_jack(known, winners)
      return jack if jack

      if mellem? && known.led_suit == "D" && known.jack_rule? && losers.any? && jack_out?(known)
        return lowest(losers)
      end

      if mellem? && winners.any? && clean_and_safe?(known)
        keeper = known.jack_keeper
        shed = highest_first(winners.reject { |card| card == QUEEN || (card == JACK_OF_DIAMONDS && known.jack_rule?) || card == keeper }).first
        return shed if shed
      end

      return highest_first(losers.reject { |card| avoid_jack?(card, known) }).first || highest_first(losers).first if losers.any?

      others = legal - [ QUEEN ]
      others = legal if others.empty?
      known.last_to_play? ? highest_first(others).first : lowest(others)
    end

    # Spec §5: a stik with nothing to lose: the bot plays last (or, in
    # spades, Q♠ can no longer come) and the stik holds no penalty cards.
    # Svær also when the seats after it can be expected to drop less than
    # SAFE_SHED points, and not in spades while Q♠ is out (spec §6).
    def clean_and_safe?(known)
      return false if known.trick_points.positive?
      return true if known.last_to_play?
      return true if svaer? && (known.led_suit != "S" || !known.queen_out?) && known.dump_risk(known.led_suit) < SAFE_SHED

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

    # Svær, J♦ −10 counted (Anders, 2026-10-25): a diamond stik is worth
    # its points plus what may still be dropped on it, less 10 for J♦.
    # - J♦ in the stik: take it while that nets less than 0; the lowest
    #   winning diamond when last, else the highest (likelier to hold).
    # - J♦ in hand: play it when it wins for sure, on the same terms.
    def count_jack(known, winners)
      return nil if known.led_suit != "D" || winners.empty?

      in_trick = known.trick_cards.include?(JACK_OF_DIAMONDS)
      sure_jack = winners.include?(JACK_OF_DIAMONDS) && (known.last_to_play? || known.top?(JACK_OF_DIAMONDS))
      return nil unless in_trick || sure_jack

      points = known.trick_points + (known.last_to_play? ? 0.0 : known.dump_risk("D"))
      return nil if points >= Knowledge::JACK_POINTS
      return JACK_OF_DIAMONDS if sure_jack

      known.last_to_play? ? lowest(winners) : highest_first(winners).first
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
      return liability_discard(known) if svaer?

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

    # Spec §5: the highest card of the shortest suit, to make a void.
    def shed_from_short_suit(known)
      discard_candidates(known).max_by { |card| [ -suit_length(known.hand, card.suit), card.rank_value ] }
    end

    # Spec §6: Svær throws off the card likeliest to win a stik later (its
    # chance to win when led), hearts first, short suits first, the higher
    # card on a tie.
    def liability_discard(known)
      candidates = discard_candidates(known)
      # J♦ −10 counted: the highest diamond above J♦ is kept to capture it.
      keeper = known.jack_keeper
      candidates -= [ keeper ] if keeper && candidates.size > 1
      candidates.max_by do |card|
        heart = card.heart? ? HEART_LIABILITY : 0.0
        [ known.win_chance(card) + heart - SHORT_LIABILITY * suit_length(known.hand, card.suit), card.rank_value ]
      end
    end

    # Under a moon threat, keep the two highest cards for the last stik;
    # with J♦ −10 on, never throw J♦ to another seat (spec §5).
    def discard_candidates(known)
      legal = known.legal
      keep = known.moon_threat ? highest_first(legal).first(2) : []
      candidates = legal - keep
      candidates = legal if candidates.empty?
      candidates -= [ JACK_OF_DIAMONDS ] if known.jack_rule? && candidates.size > 1
      candidates
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
    # With J♦ −10 on, J♦ unless it is the highest diamond out (spec §5).
    def dangerous?(card, known)
      card == QUEEN || (HIGH_SPADES.include?(card) && known.queen_out?) ||
        (card == JACK_OF_DIAMONDS && known.jack_rule? && !known.top?(card))
    end

    def lower_spades(hand) = hand.count { |card| card.suit == "S" && card.rank_value < QUEEN.rank_value }
    def other_spades(hand) = hand.count { |card| card.suit == "S" && card != QUEEN }
    def low_spades(hand) = hand.count { |card| card.suit == "S" && card.rank_value <= LOW_SPADE }
    def suit_length(hand, suit) = hand.count { |card| card.suit == suit }
    def low_cards(hand, suit) = hand.count { |card| card.suit == suit && card.rank_value <= LOW_CARD }
    def suit_strength(hand, suit) = hand.select { |card| card.suit == suit }.sum(&:rank_value)

    def lowest(cards) = cards.min_by { |card| [ card.rank_value, Card::SUITS.index(card.suit) ] }
    def highest_first(cards) = cards.sort_by { |card| [ -card.rank_value, Card::SUITS.index(card.suit) ] }
  end
end
