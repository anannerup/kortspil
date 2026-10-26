module Esmakker
  # The melder's face-down card once laid (LayFordaekt): the real `card`,
  # counting as `suit`, the called ace's, wherever it is played: led, the
  # esmakker must lay the ace on it (REGLER §2.0 "Fordækt i spillet"); when
  # the ace's suit is led, it is the melder's card to follow with.
  #
  # It ranks below every card of that suit (a stand-in; an assumption,
  # REGLER only says it "gælder som essets farve"), so the ace and any real
  # card of the suit beat it. Its code is the real card's, which the
  # per-seat views hide until its stik is taken (Play#view_for).
  class FordaektCard < Data.define(:card, :suit)
    def to_s = card.to_s
    def joker? = false
    def ace? = false
    def fordaekt? = true
    def rank_value = -1
  end
end
