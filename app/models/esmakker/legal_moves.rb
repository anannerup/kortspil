module Esmakker
  # Which cards a seat may play into a stik (REGLER §2.0, §2.13): any card
  # to lead; otherwise follow the led suit if you can; a joker may be
  # played at any time. Ticket 04 adds the called ace (the esmakker must
  # play it the first time its suit is led; it may not be trumped).
  module LegalMoves
    module_function

    def for(hand:, trick:)
      suit = trick.led_suit
      return hand if suit.nil?

      following = hand.select { |card| card.joker? || card.suit == suit }
      following.any?(&:suit) ? following : hand
    end
  end
end
