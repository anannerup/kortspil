module Esmakker
  class Svaer
    # What Svær works out from the stik played (strategy §6.1): who has
    # shown void in which suit, who discarded which suit, which suits each
    # seat led, the cards it has not seen, whether the called ace has
    # fallen, and the makker weights (until the esmakker is known).
    class Memory
      include Cards

      attr_reader :k, :trump, :void, :discards, :led, :played, :weights, :unseen, :ace_fallen

      def initialize(k, params)
        @k = k
        @params = params
        @trump = k.kind == "stik" ? k.trump : nil
        @void = Array.new(4) { [ false ] * 4 }
        @discards = Array.new(4) { [] }
        @led = Array.new(4) { [] }
        @played = Set.new
        @weights = initial_weights
        @ace_fallen = false
        k.tricks.each { |_leader, plays, _winner| read(plays) }
        read(k.trick)
        seen = Set.new(k.hand) | @played | Set.new(k.discarded)
        seen << k.fordaekt_card unless k.fordaekt_card.nil?
        @unseen = Set.new(0...DECK_SIZE) - seen
      end

      def suit_of(card) = card == FACE_DOWN ? k.called : suit(card)
      def rank_of(card) = card == FACE_DOWN ? -1 : rank(card)
      def joker_card?(card) = card != FACE_DOWN && joker?(card)

      # Who takes the stik so far (Trick#winner on a partial stik).
      def winner(plays)
        lead_seat, lead = plays.first
        trumps = plays.select { |_seat, card| !trump.nil? && trump != NT && card != FACE_DOWN && suit(card) == trump }
        return lead_seat if joker_card?(lead) && (trumps.empty? || !k.rules.joker_trumpable)
        return trumps.max_by { |_seat, card| rank(card) }.first if trumps.any?

        led = suit_of(lead)
        plays.select { |_seat, card| !joker_card?(card) && suit_of(card) == led }.max_by { |_seat, card| rank_of(card) }.first
      end

      def highest_out(suit) = unseen.select { |card| suit(card) == suit }.map { |card| rank(card) }.max || -1
      def sure?(card) = !joker?(card) && rank(card) > highest_out(suit(card))
      def trumps_out? = !trump.nil? && trump != NT && unseen.any? { |card| suit(card) == trump }

      private

      def initial_weights
        return nil if k.kind != "stik" || !k.esmakker.nil? || k.selvmakker

        seats = k.seat == k.melder ? (0..3).reject { |seat| seat == k.seat } : (0..3).reject { |seat| [ k.seat, k.melder ].include?(seat) }
        weights = seats.to_h { |seat| [ seat, Rational(1) ] }
        weights[:kitty] = @params.kitty_weight
        weights
      end

      def read(plays)
        return if plays.empty?

        led = joker_card?(plays.first.last) ? -1 : suit_of(plays.first.last)
        partial = []
        plays.each_with_index do |(seat, card), index|
          suit = suit_of(card)
          @played << card unless card == FACE_DOWN
          @ace_fallen = true if !k.called.nil? && card == ace(k.called)
          if index.zero?
            @led[seat] << suit if suit >= 0
          elsif led >= 0 && suit != led && !joker_card?(card)
            @void[seat][led] = true
            @discards[seat] << suit unless suit == trump
          end
          weigh(seat, card, suit, led, index, partial)
          partial << [ seat, card ]
        end
      end

      def weigh(seat, card, suit, led, index, partial)
        return unless weights&.key?(seat)

        weights[seat] = Rational(0) if led == k.called && index.positive? && suit != led && !joker_card?(card)
        weights[seat] *= @params.trump_lead_factor if index.zero? && seat != k.melder && !trump.nil? && trump != NT && suit == trump
        before = partial.empty? ? nil : winner(partial)
        weights[seat] *= @params.overtake_factor if before == k.melder && winner(partial + [ [ seat, card ] ]) == seat
      end
    end
  end
end
