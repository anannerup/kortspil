module Esmakker
  # How a played stik melding is settled (REGLER §2.0 "Point"), with the
  # bord's point values (Points). Es-makker is zero-sum:
  #
  # - The amount between one loser and one winner: a melding that gik hjem
  #   wins (stake + overstik) × doublings; one that went bet loses
  #   stake × missing stik × doublings.
  # - The stake is the bord's for the melding's number (8 = 1 … 13 = 3.5).
  # - The doublings multiply: påhæng (gode, halve); vip by the kitty card
  #   the melder took as trump (vip_card 1, 2 or 3; vip itself gives no
  #   doubling beyond its card, ticket 07); trumfløs; and each bank (ticket
  #   08).
  # - Who pays (Anders: "vinder fra alle modstandere og deles så med alle
  #   vindere"): two against two, each loser pays the amount and it is
  #   shared by the winners, so each winner gets the amount once and each
  #   loser pays it once. A selvmakker wins it from, or loses it to, each
  #   of the three others.
  #
  # Arithmetic is exact (Rational); amounts come back as integers when
  # whole, otherwise as floats (1.5).
  module Scoring
    module_function

    # The runde points per seat of a played stik melding: what each seat
    # won (positive) or lost (negative). Always sums to 0.
    def points(melding:, side:, stik:, trump:, values:, vip_card: nil, banks: 0)
      winners, losers = stik >= melding.number ? [ side, Seats::ALL - side ] : [ Seats::ALL - side, side ]
      per_pair = amount(melding:, stik:, trump:, values:, vip_card:, banks:)
      Seats::ALL.map do |seat|
        sign = winners.include?(seat) ? 1 : -1
        # Alone against three, the selvmakker settles with each of them.
        alone = [ winners, losers ].find(&:one?)
        tidy(sign * per_pair * (alone&.include?(seat) ? 3 : 1))
      end
    end

    # The amount of the melding (Rational): what each player wins or loses
    # two against two, and what a selvmakker settles with each opponent.
    def amount(melding:, stik:, trump:, values:, vip_card: nil, banks: 0)
      stake = exact(values.stakes.fetch(melding.number.to_s))
      factor = doublings(melding:, trump:, values:, vip_card:, banks:)
      over = stik - melding.number
      over.negative? ? stake * -over * factor : (stake + over) * factor
    end

    # The doublings multiplied together (Rational).
    def doublings(melding:, trump:, values:, vip_card: nil, banks: 0)
      factor = Rational(1)
      factor *= exact(values.pahaeng) if %i[gode halve].include?(melding.pahaeng)
      factor *= exact(vip_factor(vip_card, values)) if melding.pahaeng == :vip
      factor *= exact(values.trumflos) if trump&.trumfloes?
      factor * (exact(values.bank)**banks)
    end

    # The vip factor of the kitty card the melder took as trump: the first
    # (vip_first), second or third. Raises ArgumentError without it.
    def vip_factor(vip_card, values)
      raise ArgumentError, "a vip melding is scored by its kitty card, 1–3: #{vip_card.inspect}" unless [ 1, 2, 3 ].include?(vip_card)

      [ values.vip_first, values.vip_second, values.vip_third ].fetch(vip_card - 1)
    end

    # The runde points per seat of a sol-melding (REGLER §2.0 "Point"):
    # each sol player (players: the melder and those who went with) is
    # settled on her own with each modspiller (the seats that neither won
    # the melding nor went with), for the melding's fixed amount: she wins
    # it from each of them if she kept within the melding's stik, and pays
    # it to each of them if she was væltet. Sol players do not settle with
    # one another, and nothing doubles it (REGLER names no doublings for
    # the sol-meldinger). With no modspillere left, nobody wins anything.
    # Always sums to 0.
    def sol_points(players:, vaeltet:, amount:)
      value = exact(amount)
      modspillere = Seats::ALL - players
      totals = [ Rational(0) ] * SEAT_COUNT
      players.each do |player|
        sign = vaeltet.include?(player) ? -1 : 1
        modspillere.each do |modspiller|
          totals[player] += sign * value
          totals[modspiller] -= sign * value
        end
      end
      totals.map { |total| tidy(total) }
    end

    # Totals per seat of many runder's points, summed exactly.
    def sum(points_per_runde)
      points_per_runde.reduce([ 0 ] * SEAT_COUNT) do |totals, points|
        totals.zip(points).map { |total, amount| tidy(exact(total) + exact(amount)) }
      end
    end

    # An amount as an exact Rational: 1.5 is 3/2, 0.3 is 3/10.
    def exact(value) = Rational(value.to_s)

    # Whole amounts as integers, others as floats.
    def tidy(value) = value.denominator == 1 ? value.to_i : value.to_f
  end
end
