module Hjerterfri
  class Bot
    # What a seat knows when it is to play, read from its view
    # (Round#view_for) and limited by the bot's level (spec §2): Let
    # remembers nothing; Mellem notices where Q♠ is and who takes points;
    # Svær counts every card and infers voids. Everything here is public
    # information or the seat's own cards.
    class Knowledge
      QUEEN = Card.parse("QS")
      HIGH_SPADES = [ Card.parse("KS"), Card.parse("AS") ].freeze
      MOON_THREAT = 17 # [valgt] penalty points one seat must have alone to threaten the moon: more than Q♠ alone

      attr_reader :me, :hand, :legal, :trick, :led_suit, :totals, :end_score

      def initialize(view, level:, totals: nil, end_score: nil)
        @level = level
        @me = view[:seat]
        @hand = cards(view[:hand])
        @legal = cards(view[:legal_moves])
        @trick = (view[:current_trick] || []).map { |play| { seat: play[:seat], card: Card.parse(play[:card]) } }
        @led_suit = @trick.first&.dig(:card)&.suit
        @tricks = (view[:tricks] || []).map do |done|
          { plays: done[:plays].map { |play| { seat: play[:seat], card: Card.parse(play[:card]) } }, winner: done[:winner] }
        end
        @rules = (view[:rules] || {}).transform_keys(&:to_sym)
        @hearts_broken = view[:hearts_broken] == true
        @pass_direction = view[:pass_direction]&.to_sym
        @own_pass = cards(view[:own_pass])
        @received = cards(view[:received_cards])
        @card_counts = (view[:card_counts] || {}).to_h { |seat, count| [ seat.to_i, count ] }
        @totals = totals
        @end_score = end_score
      end

      def mellem? = @level != :let
      def svaer? = @level == :svaer

      def leading? = @trick.empty?
      def hearts_broken? = @hearts_broken
      def last_to_play? = @trick.size == Deal::SEAT_COUNT - 1
      def jack_rule? = mellem? && @rules[:jack_of_diamonds_minus_ten] == true

      # The card and seat winning the current stik so far.
      def winning_play = @trick.select { |play| play[:card].suit == led_suit }.max_by { |play| play[:card].rank_value }
      def winning_card = winning_play&.dig(:card)
      def trick_points = @trick.sum { |play| play[:card].points }
      def trick_cards = @trick.map { |play| play[:card] }

      # Every card that has left a hand in this runde (Mellem and Svær read
      # the stik; Let remembers nothing).
      def played
        return [] unless mellem?

        @played ||= @tricks.flat_map { |done| done[:plays].map { |play| play[:card] } } + trick_cards
      end

      def queen_mine? = @hand.include?(QUEEN)
      def queen_played? = played.include?(QUEEN)

      # Let assumes Q♠ is out unless it holds it.
      def queen_out? = !queen_mine? && !queen_played?

      # Where Q♠ sits, when it can be worked out for sure: the seat passed it
      # (Mellem, Svær), or every other seat but one has shown out of spades.
      def queen_holder
        return @queen_holder if defined?(@queen_holder)

        @queen_holder = find_queen_holder
      end

      # The chance each other seat holds Q♠, from what has been played and
      # thrown off (Anders, 2026-10-25: the bots watch the discards; Svær
      # really works it out, the others try a little):
      # - every level: a seat that has shown out of spades doesn't have it,
      #   and a seat known to have it has it;
      # - Mellem: a seat that threw off another card when void (where Q♠
      #   would have gone) probably doesn't have it;
      # - Svær: also a seat that followed spades under A♠/K♠ without dropping
      #   it, and the seats are weighed by how many unknown cards they hold.
      def queen_odds
        @queen_odds ||= begin
          if queen_mine? || queen_played?
            {}
          elsif (holder = queen_holder)
            others.to_h { |seat| [ seat, seat == holder ? 1.0 : 0.0 ] }
          else
            weights = others.to_h do |seat|
              weight = shown_void?(seat, "S") ? 0.0 : 1.0
              weight *= unknown_count(seat) if svaer?
              weight *= queen_evidence(seat) if mellem?
              [ seat, weight ]
            end
            sum = weights.values.sum
            sum.zero? ? {} : weights.transform_values { |weight| weight / sum }
          end
        end
      end

      # The penalty points the seat can expect to have dropped on it if it
      # takes a stik in `suit`: for each seat still to play (all others when
      # leading), the chance it is void in the suit times what it would
      # drop: 13 for Q♠ by its odds, plus about a heart. One measure for
      # every suit and every point of the runde: early a void is unlikely,
      # once the suit has gone round it is not.
      def dump_risk(suit, after: seats_after_me)
        return 0.0 if first_trick?

        after.sum do |seat|
          void = void_chance(seat, suit)
          next 0.0 if void.zero?

          queen = suit == "S" ? 0.0 : queen_odds.fetch(seat, 0.0) * QUEEN.points
          hearts = suit == "H" || void_chance(seat, "H") == 1.0 ? 0.0 : 1.0
          void * (queen + hearts)
        end
      end

      # [valgt] Expected points from which a lead counts as risky (tuned
      # 2026-10-25 on the duplicate measure, spec §8).
      RISKY = 1.0

      def risky?(suit, after: seats_after_me) = dump_risk(suit, after:) >= RISKY

      # The chance a seat is void in a suit, as well as the level can tell:
      # Let sees only who has shown out; Mellem also has a rough sense of
      # how many of the suit are gone; Svær counts it out (#void_odds).
      def void_chance(seat, suit)
        return 1.0 if shown_void?(seat, suit)
        return 0.0 unless mellem?

        void_odds(seat, suit)
      end

      def seats_after_me
        return others if leading?

        (1...(Deal::SEAT_COUNT - @trick.size)).map { |step| (me + step) % Deal::SEAT_COUNT }
      end

      # Penalty points (hearts and Q♠) taken per seat in this runde.
      def penalty_taken
        @penalty_taken ||= (0...Deal::SEAT_COUNT).map do |seat|
          @tricks.select { |done| done[:winner] == seat }.sum { |done| done[:plays].sum { |play| play[:card].points } }
        end
      end

      # The one other seat that alone has taken at least MOON_THREAT
      # penalty points, so it may be shooting the moon (spec §5).
      def moon_threat
        return nil unless mellem?

        takers = penalty_taken.each_index.select { |seat| penalty_taken[seat].positive? }
        return nil unless takers.size == 1 && takers.first != me && penalty_taken[takers.first] >= MOON_THREAT

        takers.first
      end

      # The first stik carries no points (LegalMoves), so nothing in it is risky.
      def first_trick? = @tricks.empty?

      # Whether the seat has played a card of the suit in this runde.
      def followed?(seat, suit) = all_tricks.any? { |plays| plays.any? { |play| play[:seat] == seat && play[:card].suit == suit } }

      # [udledt] The chance the giver is void in a suit (not hearts) when
      # play begins, by how many cards of it it passed this seat (0–3):
      # measured on the bots' own passes (botlab voids, 2026-10-25).
      RECEIVED_VOID = [ 0.014, 0.096, 0.33, 0.40 ].freeze
      # [udledt] The chance any other seat is void in clubs or diamonds, and
      # in spades, when play begins after a pass (a random deal: about 0.013).
      PASSED_VOID_MINOR = 0.16
      PASSED_VOID_SPADES = 0.026
      # [valgt] Mellem's rough sense: "the giver passed me 2+ cards of a
      # suit, so it is likely void in it".
      MELLEM_RECEIVED_VOID = 0.5

      # The chance the seat was void in the suit when play began, read from
      # the pass (Anders, 2026-10-25): seats pass short suits away, so the
      # giver of several cards of a suit is likely void in it (Mellem
      # roughly, Svær by how many), and after a pass any seat is likelier
      # void in clubs or diamonds than a random deal says (Svær). Nothing
      # once the seat has followed the suit. Let doesn't read the pass.
      def pass_void(seat, suit)
        return 0.0 if !mellem? || [ nil, :none ].include?(@pass_direction) || suit == "H" || followed?(seat, suit)

        received = received_from(seat, suit)
        return received >= 2 ? MELLEM_RECEIVED_VOID : 0.0 unless svaer?
        return RECEIVED_VOID[received] if giver?(seat)

        suit == "S" ? PASSED_VOID_SPADES : PASSED_VOID_MINOR
      end

      # Seats known to be void in a suit: they did not follow when it was led.
      def shown_void?(seat, suit)
        all_tricks.any? do |plays|
          plays.first[:card].suit == suit && plays.any? { |play| play[:seat] == seat && play[:card].suit != suit }
        end
      end

      # Svær counts the suits: how many of a suit are still out, and how
      # many cards each seat holds that it can't place. The chance a seat is
      # void is the chance none of the suit's unknown cards is among its
      # unknown cards (spread at random over the seats that may hold them).
      # Mellem uses the same sum roughly: every other seat holds as many
      # cards as the seat itself, and passed cards are not placed.
      def void_odds(seat, suit)
        return 1.0 if shown_void?(seat, suit)
        return 0.0 if svaer? && known_cards(seat).any? { |card| card.suit == suit }

        prior = pass_void(seat, suit)
        prior + (1.0 - prior) * dealt_void_odds(seat, suit)
      end

      # Svær: the chance from the count alone, as if the cards were dealt at random.
      def dealt_void_odds(seat, suit)
        unknown = outstanding(suit).count { |card| !svaer? || !placed?(card) }
        return 1.0 if unknown.zero?

        count = ->(other) { svaer? ? unknown_count(other) : @hand.size }
        pool = others.reject { |other| shown_void?(other, suit) }.sum(&count)
        mine = count.(seat)
        (0...unknown).reduce(1.0) { |odds, index| pool - index <= 0 ? 0.0 : odds * [ pool - mine - index, 0 ].max / (pool - index) }
      end

      # Svær: cards of the suit still in other hands.
      def outstanding(suit) = Card.deck.select { |card| card.suit == suit } - played - @hand

      # Svær: no card of its suit above it is still out.
      def top?(card) = outstanding(card.suit).none? { |other| other.rank_value > card.rank_value }

      # Svær: a rough chance that a led card wins its stik: none when every
      # card of its suit still out is higher (a sure exit), certain when none
      # is, else the share of the suit's outstanding cards below it.
      def win_chance(card)
        lower, higher = outstanding(card.suit).partition { |other| other.rank_value < card.rank_value }.map(&:size)
        return 1.0 if higher.zero?

        lower.to_f / (lower + higher)
      end

      # Svær: the penalty points it can expect from leading `card`: the
      # chance it wins the stik times what lands in it (dropped points, and
      # in hearts the hearts the others follow with plus its own).
      def lead_cost(card)
        points = dump_risk(card.suit)
        points += 1.0 + others.count { |seat| void_chance(seat, "H") < 1.0 } if card.heart?
        win_chance(card) * points
      end

      # Svær: two cards of a suit are equivalent when every card between
      # them has been played (or is in the hand).
      def equivalent?(card, other)
        low, high = [ card.rank_value, other.rank_value ].minmax
        Card::RANKS[(low + 1)...high].all? do |rank|
          between = Card.new(rank:, suit: card.suit)
          played.include?(between) || @hand.include?(between)
        end
      end

      # The hand the seat had after the pass: what it holds and has played.
      def hand_after_pass
        mine = all_tricks.flat_map { |plays| plays.select { |play| play[:seat] == me }.map { |play| play[:card] } }
        @hand + mine
      end

      # Svær's score sense: is it lowest in the spil, and would `points`
      # more bring a seat to the end score?
      def scores? = svaer? && !@totals.nil? && !@end_score.nil?
      def lowest? = scores? && @totals[me] <= @totals.min
      def over_with?(seat, points) = scores? && @totals[seat] + points >= @end_score
      def leader = scores? ? (0...Deal::SEAT_COUNT).reject { |seat| seat == me }.min_by { |seat| @totals[seat] } : nil

      private

      def others = (0...Deal::SEAT_COUNT).reject { |seat| seat == me }

      def received_from(seat, suit) = giver?(seat) ? @received.count { |card| card.suit == suit } : 0
      def giver?(seat) = @received.any? && seat == PassDirection.giver(me, @pass_direction)

      def find_queen_holder
        return nil if queen_mine? || queen_played?
        return PassDirection.receiver(me, @pass_direction) if mellem? && @own_pass.include?(QUEEN)

        candidates = others.reject { |seat| shown_void?(seat, "S") }
        candidates.one? ? candidates.first : nil
      end

      # Cards the seat knows another seat holds: the ones it passed to it,
      # until they are played (Mellem and Svær).
      def known_cards(seat)
        return [] unless mellem? && @own_pass.any? && seat == PassDirection.receiver(me, @pass_direction)

        @own_pass - played
      end

      def placed?(card) = others.any? { |seat| known_cards(seat).include?(card) }
      def unknown_count(seat) = [ @card_counts.fetch(seat, 0) - known_cards(seat).size, 0 ].max

      # How likely the seat's play so far is for Q♠'s holder: a seat that
      # threw off another card when void (Mellem, Svær), or followed a spade
      # under A♠/K♠ without dropping Q♠ (Svær), probably doesn't hold it.
      def queen_evidence(seat)
        all_tricks.reduce(1.0) do |weight, plays|
          index = plays.index { |play| play[:seat] == seat }
          next weight unless index

          card = plays[index][:card]
          led = plays.first[:card].suit
          before = plays.first(index).map { |play| play[:card] }
          if card.suit != led
            weight * 0.2
          elsif svaer? && led == "S" && card != QUEEN && before.any? { |other| other.suit == "S" && other.rank_value > QUEEN.rank_value }
            weight * 0.4
          else
            weight
          end
        end
      end

      def all_tricks = @tricks.map { |done| done[:plays] } + (@trick.empty? ? [] : [ @trick ])
      def cards(codes) = (codes || []).map { |code| code.is_a?(Card) ? code : Card.parse(code) }
    end
  end
end
