module Esmakker
  # Which cards a seat may play into a stik (REGLER §2.0, §2.11, §2.13):
  #
  # - any card to lead, a joker too;
  # - follow the led suit if you can (the melder's fordækt card counts as
  #   the called ace's suit). Holding a joker does not excuse a seat from
  #   following: "man kan ikke smide en joker, hvis man kan bekende. Man
  #   SKAL bekende" (Anders, 26 October 2026);
  # - a seat void in the led suit plays what it likes, trump and jokers
  #   included;
  # - a stik led with a joker has no suit to follow: every card is legal
  #   in it (Anders, 26 October 2026; Trick#led_suit).
  #
  # The called ace (Anders, 26 October 2026: "esmakker SKAL bekende første
  # gang kuløren spilles"): `ace` is the called ace when the seat is the
  # esmakker holding it and its suit has not been led yet (Play#ace_owed).
  # Then, when its suit is led (a real card or the fordækt card), the ace
  # is the only card she may play (the strictest reading); and when she
  # leads, she may lead the suit only with the ace. Nobody
  # else is bound by it: a seat void in the suit may trump the ace, before
  # or after it falls ("man kan godt stikke makkers es").
  module LegalMoves
    module_function

    def for(hand:, trick:, ace: nil)
      return owed(hand:, trick:, ace:) if ace

      suit = trick.led_suit
      return hand if suit.nil?

      following = hand.select { |card| !card.joker? && card.suit == suit }
      following.any? ? following : hand
    end

    # Why `card` (in the hand) may not be played, nil when it may.
    def rejection(card:, hand:, trick:, ace: nil)
      return nil if self.for(hand:, trick:, ace:).include?(card)

      self.for(hand:, trick:).include?(card) ? :must_play_called_ace : :must_follow_suit
    end

    # The esmakker's cards while she owes the ace: the ace alone in a stik
    # led in its suit; leading, anything but another card of its suit.
    def owed(hand:, trick:, ace:)
      return [ ace ] if trick.led_suit == ace.suit
      return hand.reject { |card| !card.joker? && card.suit == ace.suit && card != ace } if trick.empty?

      self.for(hand:, trick:)
    end
  end
end
