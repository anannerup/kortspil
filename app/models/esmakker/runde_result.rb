module Esmakker
  # How a runde with a melder ended (Round#result), for the runde's result
  # and the spil's score sheet:
  #
  # - kind :played: a stik melding played through. The melder and the
  #   esmakker (or the selvmakker alone, `esmakker` nil) took `stik`
  #   together; the melding gik hjem (#gik_hjem?) when that is at least its
  #   number. `tricks_won` is the stik per seat. `points` are the runde
  #   points per seat by the bord's point values (Scoring); they sum to 0.
  # - kind :not_played: a melding whose play is not built yet (the
  #   sol-meldinger; tickets 09, 10). The runde counts, nobody plays it,
  #   and it scores 0.
  #
  # `vip_card` is the kitty card a vip melder took as trump (1–3; vip
  # itself gives no doubling beyond it), and `banks` the number of banks
  # (ticket 08); each is a doubling (Scoring).
  class RundeResult < Data.define(:kind, :melder, :melding, :trump, :called_ace, :esmakker, :selvmakker, :tricks_won, :vip_card, :banks, :points)
    NO_POINTS = ([ 0 ] * SEAT_COUNT).freeze

    def self.not_played(melder:, melding:)
      new(kind: :not_played, melder:, melding:, trump: nil, called_ace: nil, esmakker: nil, selvmakker: false, tricks_won: [],
          vip_card: nil, banks: 0, points: NO_POINTS)
    end

    # values: the bord's point values (Points) the runde is settled with.
    def self.played(melder:, melding:, trump:, called_ace:, esmakker:, selvmakker:, tricks_won:, values:, vip_card: nil, banks: 0)
      side = [ melder, esmakker ].compact
      points = Scoring.points(melding:, side:, stik: side.sum { |seat| tricks_won[seat] }, trump:, values:, vip_card:, banks:)
      new(kind: :played, melder:, melding:, trump:, called_ace:, esmakker:, selvmakker:, tricks_won: tricks_won.dup.freeze,
          vip_card:, banks:, points: points.freeze)
    end

    def played? = kind == :played

    # The melder's side: the melder and the esmakker, or the selvmakker.
    def side = [ melder, esmakker ].compact

    def stik = played? ? side.sum { |seat| tricks_won[seat] } : 0

    def gik_hjem? = played? && stik >= melding.number

    def to_h
      { kind:, melder:, melding: melding.to_s, trump: trump&.to_s, called_ace:, esmakker:, selvmakker:,
        tricks_won:, stik:, gik_hjem: gik_hjem?, vip_card:, banks:, points: }
    end
  end
end
