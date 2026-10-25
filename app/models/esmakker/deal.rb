module Esmakker
  # The 55 cards dealt: 13 to each seat, in seat order, and 3 to the kitty
  # (katten). Stored as 55 space-separated card codes: the four hands, then
  # the kitty.
  class Deal < Data.define(:hands, :kitty)
    HAND_SIZE = 13
    KITTY_SIZE = 3

    def self.shuffled(shuffler: Random.new)
      cards = Card.deck.shuffle(random: shuffler)
      new(hands: cards.first(SEAT_COUNT * HAND_SIZE).each_slice(HAND_SIZE).to_a, kitty: cards.last(KITTY_SIZE))
    end

    def self.parse(string)
      cards = string.to_s.split.map { |code| Card.parse(code) }
      new(hands: cards.first(SEAT_COUNT * HAND_SIZE).each_slice(HAND_SIZE).to_a, kitty: cards.drop(SEAT_COUNT * HAND_SIZE))
    end

    def initialize(hands:, kitty:)
      unless hands.size == SEAT_COUNT && hands.all? { |hand| hand.size == HAND_SIZE } && kitty.size == KITTY_SIZE
        raise ArgumentError, "a deal is #{SEAT_COUNT} hands of #{HAND_SIZE} cards and a kitty of #{KITTY_SIZE}"
      end
      raise ArgumentError, "a deal holds each card of the deck once" unless (hands.flatten + kitty).uniq.size == Card.deck.size

      super(hands: hands.map { |hand| hand.dup.freeze }.freeze, kitty: kitty.dup.freeze)
    end

    def hand(seat) = hands.fetch(seat)
    def to_s = (hands.flatten + kitty).join(" ")
  end
end
