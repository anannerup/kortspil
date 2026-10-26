module Esmakker
  # Which cards a seat may play into a stik (REGLER §2.0, §2.11, §2.13):
  #
  # - any card to lead;
  # - the esmakker must lay the called ace the first time its suit is led
  #   (§2.0 "Esset må ikke stikkes"): in a stik led in the ace's suit (the
  #   fordækt card counts as that suit) the ace is her only card. A stik
  #   led with a joker is not led in the suit, even when the next card sets
  #   that suit to follow;
  # - otherwise follow the led suit if you can; a joker may be played at
  #   any time (§2.13);
  # - a seat void in the led suit plays what it likes, except that once
  #   the called ace lies in a stik led in its suit, it may not play trump
  #   on it ("esset må ikke stikkes"), unless it holds nothing but trump.
  #   (Who plays before the ace may trump, but the ace takes the stik
  #   anyway: Trick#winner.)
  #
  # `called_ace` is the called ace's suit when there is an esmakker; nil
  # otherwise (no called ace yet, or the melder is selvmakker: the two ace
  # rules are the esmakker's). The hand may hold the melder's FordaektCard.
  module LegalMoves
    module_function

    def for(hand:, trick:, trump: nil, called_ace: nil)
      return hand if trick.empty?
      return [ ace(called_ace) ] if must_play_ace?(hand, trick, called_ace)

      suit = trick.led_suit
      return hand if suit.nil?

      following = hand.select { |card| card.joker? || card.suit == suit }
      return following if following.any? { |card| !card.joker? }
      return hand unless trick.protected_ace_seat(called_ace) && trump && !trump.trumfloes?

      others = hand.reject { |card| !card.joker? && card.suit == trump.suit }
      others.empty? ? hand : others
    end

    # Why `card` (in the hand) may not be played, nil when it may.
    def rejection(card:, hand:, trick:, trump: nil, called_ace: nil)
      return nil if self.for(hand:, trick:, trump:, called_ace:).include?(card)
      return :must_play_ace if must_play_ace?(hand, trick, called_ace)
      return :may_not_trump_ace if trick.protected_ace_seat(called_ace) && !card.joker? && card.suit == trump&.suit

      :must_follow_suit
    end

    def must_play_ace?(hand, trick, called_ace)
      !called_ace.nil? && trick.led_in?(called_ace) && hand.include?(ace(called_ace))
    end

    def ace(suit) = Card.new(rank: "A", suit:)
  end
end
