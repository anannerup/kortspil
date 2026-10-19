module Hjerterfri
  # Which cards the seat to act may play (docs/rules §3.4–3.5). The single
  # source for both the legal moves a view shows and the reason a play is
  # rejected.
  class LegalMoves
    def initialize(hand:, trick:, first_trick:, hearts_broken:)
      @hand = hand
      @trick = trick
      @first_trick = first_trick
      @hearts_broken = hearts_broken
    end

    def cards
      restrictions.reduce(@hand) { |allowed, (_reason, permits)| narrow(allowed, permits) }
    end

    # The reason the card may not be played, or nil when it may.
    def rejection_for(card)
      return :card_not_in_hand unless @hand.include?(card)

      restrictions.reduce(@hand) do |allowed, (reason, permits)|
        narrowed = narrow(allowed, permits)
        return reason unless narrowed.include?(card)

        narrowed
      end
      nil
    end

    private

    # Applied in order, each keeping only the cards it permits. A restriction
    # never empties the hand: if no card qualifies ("unless you hold nothing
    # else"), every card still allowed stays allowed.
    def restrictions
      leading = @trick.empty?
      [
        ([ :must_lead_two_of_clubs, ->(card) { card == Card::TWO_OF_CLUBS } ] if leading && @first_trick),
        ([ :must_follow_suit, ->(card) { card.suit == @trick.led_suit } ] unless leading),
        ([ :no_points_on_first_trick, ->(card) { !card.penalty? } ] if @first_trick),
        ([ :hearts_not_broken, ->(card) { !card.heart? } ] if leading && !@hearts_broken)
      ].compact
    end

    def narrow(allowed, permits)
      kept = allowed.select(&permits)
      kept.empty? ? allowed : kept
    end
  end
end
