module Esmakker
  # Fordækt (REGLER §2.0 "Fordækt", "Fordækt i spillet"; §2.12): a melder
  # with no card in the called ace's suit after the kitty may, before the
  # first stik, lay one card (a joker too) face down on the table
  # (FordaektCard), never turned. The intent: the melder lays `card` (a
  # Card or a Joker, or nil for a code that is no card, which the runde
  # rejects) face down.
  class LayFordaekt < Data.define(:card)
    def to_h = { card: card&.to_s }
  end
end
