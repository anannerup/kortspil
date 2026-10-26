module Esmakker
  class Svaer
    # Svær in the meldingsrunde (strategy §6.3): it goes with on a sol
    # melding it passes the test for, says "det kan jeg selv" on a melding
    # it would bid itself, and otherwise bids the legal melding with the
    # highest risk-weighted value, P(hjem) × gain − P(bet) × loss
    # (Anders), among those it is willing to bid: stik meldinger up to
    # Nmax, gode, halve and vip by their conditions, the sol-meldinger its
    # hand passes the test for. Pas when none is worth anything.
    module Meldingsrunde
      include Cards
      extend Cards

      module_function

      def bid(k, params)
        values = Hand.estimates(k.hand, params)
        own = values.max - params.makker_stik
        current = k.melding
        if k.can_med && current && sol?(current) && Hand.sol_passes?(current, k.hand, params)
          value = Hand.sol_value_of(current, k.rules.points, params)
          return [ [ :med ], Svaer.thought("gaa_med", "sol_test", current, expect(current, value, own, params)) ]
        end
        if k.can_selv && current
          value = candidate_value(k, current, values, params)
          return [ [ :selv ], Svaer.thought("det_kan_jeg_selv", "within_reach", current, expect(current, value, own, params)) ] if value&.positive?
        end
        best = nil
        k.bids.each do |melding|
          value = candidate_value(k, melding, values, params)
          best = [ melding, value ] if value&.positive? && (best.nil? || value > best.last)
        end
        if best
          melding, value = best
          reason = sol?(melding) ? "sol_test" : "bid_#{%w[lowest gode halve vip][pahaeng(melding)]}"
          return [ [ :bid, melding ], Svaer.thought("bid", reason, melding, expect(melding, value, own, params)) ]
        end
        [ [ :pas ], Svaer.thought("pas", Hand.nmax(values.max, params).nil? ? "pas_weak" : "pas_too_high") ]
      end

      def expect(melding, value, own, params)
        expect = Svaer.no_expect(melding)
        expect[:stik] = { self: num(own), makker: num(params.makker_stik) } unless sol?(melding)
        expect[:points] = num(value)
        expect
      end

      # The risk-weighted value of bidding `melding`, or nil when Svær is
      # not willing to (§6.3).
      def candidate_value(k, melding, values, params)
        points = k.rules.points
        hand = k.hand
        return Hand.sol_passes?(melding, hand, params) ? Hand.sol_value_of(melding, points, params) : nil if sol?(melding)

        number = number(melding)
        s_best = values.max
        top = Hand.nmax(s_best, params)
        case pahaeng(melding)
        when 0
          return nil if top.nil? || number > top

          best = 0
          (1..4).each { |trump| best = trump if values[trump] > values[best] }
          Hand.stik_value(melding, values[best], best, points, params)
        when 1
          return nil unless values[0] >= number + params.gode_margin && values[0] >= s_best - params.gode_close

          Hand.stik_value(melding, values[0], 0, points, params)
        when 2
          return nil if top.nil? || number > top || values[NT] < number || !halve_shape?(hand, values, params)

          trump = Hand.best_suit(values)
          Hand.stik_value(melding, values[trump], trump, points, params)
        when 3
          return nil unless (0..3).all? { |trump| values[trump] >= number + params.vip_margin } && values[NT] >= number

          Hand.stik_value(melding, values[0..3].min, 1, points, params)
        end
      end

      def halve_shape?(hand, values, params)
        called = Hand.call_choice(hand, Hand.best_suit(values), Hand.free_aces(hand))
        (0..3).all? do |suit|
          ranks = ranks_in(hand, suit)
          next false if ranks.empty?
          next true if suit == called

          ranks.size >= params.halve_min_length && (ranks & [ ACE, KING, QUEEN ]).any?
        end
      end
    end
  end
end
