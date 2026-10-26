module Esmakker
  # How a runde with a melder ended (Round#result), for the runde's result
  # and the spil's overview:
  #
  # - kind :played: a stik melding played through. The melder and the
  #   esmakker (or the selvmakker alone, `esmakker` nil) took `stik`
  #   together; the melding gik hjem (#gik_hjem?) when that is at least its
  #   number. `tricks_won` is the stik per seat.
  # - kind :not_played: a melding whose play is not built yet (vip,
  #   sol-meldinger; tickets 07, 09, 10). The runde counts, nobody
  #   plays it, and it scores nothing.
  #
  # Points come in ticket 05; until then every runde scores 0.
  class RundeResult < Data.define(:kind, :melder, :melding, :trump, :called_ace, :esmakker, :selvmakker, :tricks_won)
    def self.not_played(melder:, melding:)
      new(kind: :not_played, melder:, melding:, trump: nil, called_ace: nil, esmakker: nil, selvmakker: false, tricks_won: [])
    end

    def self.played(melder:, melding:, trump:, called_ace:, esmakker:, selvmakker:, tricks_won:)
      new(kind: :played, melder:, melding:, trump:, called_ace:, esmakker:, selvmakker:, tricks_won: tricks_won.dup.freeze)
    end

    def played? = kind == :played

    # The melder's side: the melder and the esmakker, or the selvmakker.
    def side = [ melder, esmakker ].compact

    def stik = played? ? side.sum { |seat| tricks_won[seat] } : 0

    def gik_hjem? = played? && stik >= melding.number

    # The runde points per seat (ticket 05).
    def points = [ 0 ] * SEAT_COUNT

    def to_h
      { kind:, melder:, melding: melding.to_s, trump: trump&.to_s, called_ace:, esmakker:, selvmakker:,
        tricks_won:, stik:, gik_hjem: gik_hjem?, points: }
    end
  end
end
