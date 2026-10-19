module Hjerterfri
  # A playing card. Its code is rank + suit: "2C", "TD", "QS", "AH".
  class Card < Data.define(:rank, :suit)
    RANKS = %w[2 3 4 5 6 7 8 9 T J Q K A].freeze
    SUITS = %w[C D H S].freeze
    # Hands are shown with the colours alternating: clubs, diamonds, spades, hearts.
    DISPLAY_SUITS = %w[C D S H].freeze

    def self.valid?(code)
      code.is_a?(String) && code.size == 2 && RANKS.include?(code[0]) && SUITS.include?(code[1])
    end

    def self.parse(code)
      raise ArgumentError, "not a card code: #{code.inspect}" unless valid?(code)

      new(rank: code[0], suit: code[1])
    end

    def self.deck
      SUITS.product(RANKS).map { |suit, rank| new(rank:, suit:) }
    end

    def to_s = "#{rank}#{suit}"
    def rank_value = RANKS.index(rank)
    def display_key = [ DISPLAY_SUITS.index(suit), rank_value ]
    def heart? = suit == "H"
    def queen_of_spades? = rank == "Q" && suit == "S"
    def penalty? = points.positive?

    def points
      return 1 if heart?
      return 13 if queen_of_spades?

      0
    end

    TWO_OF_CLUBS = new(rank: "2", suit: "C")
    JACK_OF_DIAMONDS = new(rank: "J", suit: "D")
  end
end
