module Esmakker
  # How a runde won on a sol-melding ended (SolPlay#result), for the runde's
  # result and the spil's score sheet: who played it (`players`: the melder,
  # then those who went with), the most stik it allowed, who was væltet,
  # the stik per seat and the runde points per seat (Scoring.sol_points).
  # Answers what the score needs as RundeResult does (#points, #to_h); its
  # kind is :sol.
  class SolResult < Data.define(:melder, :melding, :players, :most_stik, :vaeltet, :tricks_won, :points)
    # values: the bord's point values (Points); the melding's fixed amount
    # is its own (sol, ren_sol).
    def self.settled(melder:, melding:, players:, most_stik:, vaeltet:, tricks_won:, values:)
      points = Scoring.sol_points(players:, vaeltet:, amount: values.public_send(melding.kind))
      new(melder:, melding:, players: players.dup.freeze, most_stik:, vaeltet: vaeltet.dup.freeze, tricks_won: tricks_won.dup.freeze, points: points.freeze)
    end

    def kind = :sol

    # The sol players who kept within the melding's stik.
    def klaret = players - vaeltet

    # The stik melding's fields are there, empty, so the client reads every
    # result alike; `sol` holds what is the sol-melding's own.
    def to_h
      { kind:, melder:, melding: melding.to_s, trump: nil, called_ace: nil, esmakker: nil, selvmakker: false,
        tricks_won:, stik: tricks_won[melder], gik_hjem: !vaeltet.include?(melder), vip_card: nil, banks: 0, points:,
        sol: { players:, most_stik:, vaeltet: } }
    end
  end
end
