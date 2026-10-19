module Hjerterfri
  # Where the three passed cards go (docs/rules §3.3). Seats 0–3 sit
  # clockwise, so the player on your left is the next seat clockwise:
  # left is seat + 1, right is seat − 1, across is seat + 2.
  module PassDirection
    CYCLE = %i[left right across none].freeze
    OFFSETS = { left: 1, right: Deal::SEAT_COUNT - 1, across: 2, none: 0 }.freeze

    # Runde 1 left, 2 right, 3 across, 4 none, then the pattern repeats.
    def self.for_runde(number)
      raise ArgumentError, "runde numbers start at 1: #{number.inspect}" unless number.is_a?(Integer) && number.positive?

      CYCLE[(number - 1) % CYCLE.size]
    end

    # Accepts a symbol or its stored string ("left").
    def self.parse(value)
      direction = value.to_s.to_sym
      raise ArgumentError, "not a pass direction: #{value.inspect}" unless OFFSETS.key?(direction)

      direction
    end

    def self.receiver(seat, direction) = (seat + OFFSETS.fetch(direction)) % Deal::SEAT_COUNT
    def self.giver(seat, direction) = (seat - OFFSETS.fetch(direction)) % Deal::SEAT_COUNT
  end
end
