module Hjerterfri
  # The cards each seat has chosen to pass in a runde: one slot per seat,
  # nil until that seat has passed.
  #
  # Stored as 12 space-separated tokens, 3 per seat in seat order. A seat
  # that has not passed yet fills its 3 slots with "--". No passes at all
  # (and every runde without passing) is the empty string.
  #
  #   "QS AH KH -- -- -- 2D 3D 4D -- -- --"   seats 0 and 2 have passed
  class Passes < Data.define(:slots)
    SIZE = 3
    EMPTY_SLOT = "--".freeze

    def self.none = new(slots: Array.new(Deal::SEAT_COUNT))

    def self.parse(string)
      codes = string.split
      return none if codes.empty?
      raise ArgumentError, "passes are #{Deal::SEAT_COUNT * SIZE} slots" unless codes.size == Deal::SEAT_COUNT * SIZE

      new(slots: codes.each_slice(SIZE).map { |slot| slot.all?(EMPTY_SLOT) ? nil : slot.map { |code| Card.parse(code) } })
    end

    def initialize(slots:)
      unless slots.size == Deal::SEAT_COUNT && slots.all? { |slot| slot.nil? || slot.size == SIZE }
        raise ArgumentError, "passes are #{Deal::SEAT_COUNT} slots of nil or #{SIZE} cards"
      end

      super(slots: slots.map { |slot| slot&.map { |card| card.is_a?(Card) ? card : Card.parse(card) }&.freeze }.freeze)
    end

    def of(seat) = slots.fetch(seat) || []
    def passed?(seat) = !slots.fetch(seat).nil?
    def passed_seats = slots.each_index.select { |seat| passed?(seat) }
    def none? = slots.none?
    def complete? = slots.all?

    def add(seat, cards) = Passes.new(slots: slots.dup.tap { |copy| copy[seat] = cards })

    def to_s
      return "" if none?

      slots.flat_map { |slot| slot ? slot.map(&:to_s) : [ EMPTY_SLOT ] * SIZE }.join(" ")
    end
  end
end
