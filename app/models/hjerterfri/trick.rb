module Hjerterfri
  # One stik: up to four cards in play order, starting with the leader's.
  class Trick < Data.define(:leader, :cards)
    def self.led_by(seat) = new(leader: seat, cards: [])

    def initialize(leader:, cards:)
      super(leader:, cards: cards.dup.freeze)
    end

    def add(card) = Trick.new(leader:, cards: [ *cards, card ])
    def empty? = cards.empty?
    def complete? = cards.size == Deal::SEAT_COUNT
    def to_act = seat_at(cards.size)
    def led_suit = cards.first&.suit
    def points = cards.sum(&:points)

    # The highest card of the led suit takes the stik; there is no trump.
    def winner
      winning = cards.select { |card| card.suit == led_suit }.max_by(&:rank_value)
      seat_at(cards.index(winning))
    end

    def plays
      cards.each_with_index.map { |card, index| { seat: seat_at(index), card: card.to_s } }
    end

    private

    def seat_at(index) = (leader + index) % Deal::SEAT_COUNT
  end
end
