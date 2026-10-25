module Esmakker
  # A jernhånd (REGLER §2.0, §2.4): 13 cards with no picture cards, no aces
  # and no jokers. Its holder may claim a new deal before the bidding.
  module Jernhaand
    HAND_SIZE = 13
    NUMBER_CARD = /\A(?:[2-9T]|10)[CDHS]\z/

    # cards: card codes ("7H", "TC" or "10C") or cards whose #to_s is such a code.
    # Only number cards 2–10 qualify, so any other code (picture card, ace,
    # joker, whatever its spelling) means it is no jernhånd.
    def self.hand?(cards)
      cards.size == HAND_SIZE && cards.all? { |card| NUMBER_CARD.match?(card.to_s) }
    end
  end
end
