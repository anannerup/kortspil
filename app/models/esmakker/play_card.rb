module Esmakker
  # A seat plays a card into the stik (a Card or Joker, or nil for a code
  # that is no card, which the runde rejects).
  class PlayCard < Data.define(:card)
    def to_h = { card: card&.to_s }
  end
end
