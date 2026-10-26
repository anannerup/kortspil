module Esmakker
  # A card of the es-makker deck: the 52 playing cards, coded rank + suit
  # as in hjerterfri ("2C", "TD", "QS", "AH"), and three jokers, coded
  # "X1", "X2", "X3". No playing card's code starts with X, so the two can
  # never be confused.
  class Card < Data.define(:rank, :suit)
    RANKS = %w[2 3 4 5 6 7 8 9 T J Q K A].freeze
    SUITS = %w[C D H S].freeze
    # Hands are shown with the colours alternating, jokers last.
    DISPLAY_SUITS = %w[C D S H].freeze

    def self.valid?(code) = Joker.valid?(code) || playing_card?(code)

    def self.parse(code)
      return Joker.parse(code) if Joker.valid?(code)
      raise ArgumentError, "not a card code: #{code.inspect}" unless playing_card?(code)

      new(rank: code[0], suit: code[1])
    end

    def self.playing_card?(code)
      code.is_a?(String) && code.size == 2 && RANKS.include?(code[0]) && SUITS.include?(code[1])
    end

    # The 55 cards: 52 playing cards and three jokers.
    def self.deck = SUITS.product(RANKS).map { |suit, rank| new(rank:, suit:) } + Joker.all

    def to_s = "#{rank}#{suit}"
    def joker? = false
    def fordaekt? = false
    def ace? = rank == "A"
    def rank_value = RANKS.index(rank)
    def display_key = [ DISPLAY_SUITS.index(suit), rank_value ]
  end
end
