module Esmakker
  # Which cards a seat may play into a stik (REGLER §2.0, §2.11, §2.13):
  #
  # - any card to lead;
  # - follow the led suit if you can (the melder's fordækt card counts as
  #   the called ace's suit); a joker may be played at any time (§2.13);
  # - a seat void in the led suit plays what it likes, trump included;
  # - a stik led with a joker has no suit to follow: every card is legal
  #   in it (Anders, 26 October 2026; Trick#led_suit).
  #
  # The called ace has no rules of its own (Anders, 26 October 2026): the
  # esmakker is not forced to lay it when its suit is led ("highly
  # encouraged", not required), and a seat void in the suit may trump it,
  # before or after it falls ("man kan godt stikke makkers es").
  module LegalMoves
    module_function

    def for(hand:, trick:)
      suit = trick.led_suit
      return hand if suit.nil?

      following = hand.select { |card| card.joker? || card.suit == suit }
      following.any? { |card| !card.joker? } ? following : hand
    end

    # Why `card` (in the hand) may not be played, nil when it may.
    def rejection(card:, hand:, trick:)
      self.for(hand:, trick:).include?(card) ? nil : :must_follow_suit
    end
  end
end
