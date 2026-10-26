module Esmakker
  # The melder's face-down card once laid (LayFordaekt): the real `card`
  # (any card, a joker too: Anders, 26 October 2026), lying on the table,
  # counting as `suit`, the called ace's, wherever it is played: led, it
  # is a lead in the ace's suit; when someone else leads the ace's suit, it
  # is the melder's card to follow with (REGLER §2.0 "Fordækt i spillet").
  # A joker laid fordækt is no joker in play: it is a card of the suit.
  #
  # It ranks below every card of that suit (an assumption, REGLER only says
  # it "gælder som essets farve"): any real card of the suit, and any
  # trump, beats it, so it takes a stik only when it was led and nobody
  # followed the suit or trumped. Its face is the melder's secret for good:
  # the per-seat views never show it to anyone else (Play#view_for), and
  # it is never turned.
  class FordaektCard < Data.define(:card, :suit)
    def to_s = card.to_s
    def joker? = false
    def ace? = false
    def fordaekt? = true
    def rank_value = -1
  end
end
