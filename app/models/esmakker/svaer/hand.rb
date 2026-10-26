module Esmakker
  class Svaer
    # Svær's judgement of a hand (strategy §6.2, §6.3, §6.7): the stik it
    # takes itself per trump, the ace it would call, Nmax, the sol test and
    # the risk-weighted value of a melding. Exact (Rational).
    module Hand
      include Cards
      extend Cards

      SAFE = 2
      ALMOST = 1
      DANGER = 0

      module_function

      def quick_tricks(ranks)
        if ranks.include?(ACE)
          return Rational(3) if ranks.include?(KING) && ranks.include?(QUEEN)
          return Rational(2) if ranks.include?(KING)
          return Rational(3, 2) if ranks.include?(QUEEN)

          return Rational(1)
        end
        return Rational(0) unless ranks.include?(KING)
        return Rational(1) if ranks.include?(QUEEN)

        ranks.size >= 2 ? Rational(1, 2) : Rational(0)
      end

      def trump_stik(ranks)
        value = Rational(0)
        value += 1 if ranks.include?(ACE)
        value += 1 if ranks.include?(KING) && ranks.size >= 2
        value += 1 if ranks.include?(QUEEN) && ranks.size >= 3
        value + [ 0, ranks.size - 3 ].max
      end

      def called_stik(ranks)
        return Rational(3, 2) if ranks.include?(KING) && ranks.include?(QUEEN)
        return Rational(1) if ranks.include?(KING) && ranks.size >= 2

        Rational(0)
      end

      # The stik the hand takes itself with `trump`, the makker holding the
      # ace of `called` (§6.2).
      def own_stik(hand, trump, called, params)
        total = Rational(hand.count { |card| joker?(card) })
        (0..3).each do |suit|
          ranks = ranks_in(hand, suit)
          length = ranks.size
          if trump == NT
            total += quick_tricks(ranks)
            total += params.nt_long_bonus * (length - 4) if length > 4 && ([ ACE, KING, QUEEN ] - ranks).empty?
          elsif suit == trump
            total += trump_stik(ranks)
          elsif suit == called
            total += called_stik(ranks)
          else
            total += quick_tricks(ranks)
            total += params.long_ak_bonus * (length - 4) if length > 4 && ranks.include?(ACE) && ranks.include?(KING)
          end
        end
        total
      end

      # §6.4: among the aces it may call, not trump, the shortest suit; on a
      # tie the one where it holds the highest card, then the lowest suit.
      def call_choice(hand, trump, callable)
        options = callable.reject { |suit| suit == trump }
        options = callable if options.empty?
        options.min_by do |suit|
          ranks = ranks_in(hand, suit)
          [ ranks.size, -(ranks.last || -1), suit ]
        end
      end

      def free_aces(hand)
        free = (0..3).reject { |suit| hand.include?(ace(suit)) }
        free.empty? ? [ 0, 1, 2, 3 ] : free
      end

      # S per trump 0–4: its own stik plus makker's.
      def estimates(hand, params, called = nil)
        (0..4).map do |trump|
          own_stik(hand, trump, called.nil? ? call_choice(hand, trump, free_aces(hand)) : called, params) + params.makker_stik
        end
      end

      def own_estimates(hand, params, called = nil) = estimates(hand, params, called).map { |value| value - params.makker_stik }

      def best_suit(values)
        best = 0
        (1..3).each { |trump| best = trump if values[trump] > values[best] }
        best
      end

      # The highest stik melding Svær goes to, or nil (§6.3).
      def nmax(s_best, params)
        top = nil
        Melding::NUMBERS.each { |number| top = number if s_best >= number + params.nmax_margin }
        top = 8 if top.nil? && s_best >= 8
        top
      end

      # --- §6.7 the sol test ---

      def safe?(values)
        return true if values.empty?
        return false if values.each_with_index.any? { |value, index| value > 2 * index + 1 }

        values.size < 4 || values.first == 1
      end

      def suit_level(values, params)
        values = values.sort
        return SAFE if safe?(values)
        return ALMOST if values.size <= 2 && values.first <= params.sol_almost_low
        return ALMOST if values.size >= 3 && safe?(values[0...-1])

        DANGER
      end

      def sol_values(hand, suit) = hand.select { |card| suit(card) == suit }.map { |card| sol_value(card) }.sort

      def sol_passes?(melding, hand, params)
        levels = (0..3).map { |suit| suit_level(sol_values(hand, suit), params) }
        lengths = (0..3).map { |suit| sol_values(hand, suit).size }
        danger = (0..3).select { |suit| levels[suit] == DANGER }
        almost = (0..3).select { |suit| levels[suit] == ALMOST }
        case melding
        when REN_BORDLAEGGER then danger.empty? && almost.empty?
        when BORDLAEGGER
          unsafe = danger + almost
          unsafe.empty? || (unsafe.size == 1 && lengths[unsafe.first] == 1)
        when REN_SOL then danger.empty? && almost.size <= 1
        when SOL then danger.empty? || (danger.size == 1 && lengths[danger.first] <= 2)
        else false
        end
      end

      # --- §6.3 risk-weighted value ---

      def p_hjem(s, number, params) = (Rational(1, 2) + (s - number) / (2 * params.p_width)).clamp(Rational(0), Rational(1))

      def exact(value) = Rational(value.to_s)

      def stik_factor(melding, trump, points, vip_card = nil, banks = 0)
        pahaeng = pahaeng(melding)
        factor = Rational(1)
        factor *= exact(points.pahaeng) if [ 1, 2 ].include?(pahaeng)
        factor *= exact([ points.vip_first, points.vip_second, points.vip_third ][(vip_card || 1) - 1]) if pahaeng == 3
        factor *= exact(points.trumflos) if trump == NT
        factor *= exact(points.klor) if [ 2, 3 ].include?(pahaeng) && trump == 0
        factor * exact(points.bank)**banks
      end

      # P(hjem) × gain − P(bet) × loss for the melder's side, per seat.
      def stik_value(melding, s, trump, points, params, vip_card = nil, banks = 0)
        number = number(melding)
        stake = exact(points.stakes.fetch(number.to_s))
        factor = stik_factor(melding, trump, points, vip_card, banks)
        over = [ 0, s.floor - number ].max
        chance = p_hjem(s, number, params)
        chance * (stake + over) * factor - (1 - chance) * stake * params.expected_bet * factor
      end

      def sol_value_of(melding, points, params)
        amount = exact(points.public_send(SOL_KINDS[melding - SOL])) * 3
        chance = params.sol_p[melding - SOL]
        chance * amount - (1 - chance) * amount
      end
    end
  end
end
