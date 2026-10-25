module Esmakker
  # The melder, holding the kitty, lays three cards away that nobody sees
  # (Card, or nil for a code that is no card, which the runde rejects).
  class Discard < Data.define(:cards)
    def to_h = { cards: cards.map { |card| card&.to_s } }
  end
end
