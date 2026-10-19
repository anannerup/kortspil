module Hjerterfri
  # The 52 cards dealt to the four seats, 13 each, in seat order.
  # Stored as 52 space-separated card codes.
  class Deal < Data.define(:hands)
    SEAT_COUNT = 4
    HAND_SIZE = 13

    def self.shuffled(shuffler: Random.new)
      new(hands: Card.deck.shuffle(random: shuffler).each_slice(HAND_SIZE).to_a)
    end

    def self.parse(string)
      new(hands: string.split.map { |code| Card.parse(code) }.each_slice(HAND_SIZE).to_a)
    end

    def initialize(hands:)
      unless hands.size == SEAT_COUNT && hands.all? { |hand| hand.size == HAND_SIZE }
        raise ArgumentError, "a deal is #{SEAT_COUNT} hands of #{HAND_SIZE} cards"
      end
      raise ArgumentError, "a deal holds each card of the deck once" unless hands.flatten.uniq.size == Card.deck.size

      super(hands: hands.map { |hand| hand.dup.freeze }.freeze)
    end

    def hand(seat) = hands.fetch(seat)
    def holder_of(card) = hands.index { |hand| hand.include?(card) }
    def to_s = hands.flatten.join(" ")
  end
end
