module Esmakker
  # What the melder names after winning a stik melding (REGLER §2.0
  # "Almindelig melding"): a suit is trump, or nothing is (trumfløs; Sans
  # is the same thing). Trumfløs is no melding and no påhæng, only this
  # choice. Gode means clubs (§2.0 "Gode").
  #
  # Codes, for views and the action log: "C", "D", "H", "S", "trumfloes".
  class Trump < Data.define(:suit)
    TRUMFLOES = "trumfloes"
    CODES = [ *Card::SUITS, TRUMFLOES ].freeze

    def self.trumfloes = new(suit: nil)
    def self.clubs = new(suit: "C")

    # Every choice: the four suits, then trumfløs.
    def self.all = CODES.map { |code| parse(code) }

    def self.valid?(code) = CODES.include?(code)

    # Raises ArgumentError on a code that is no trump.
    def self.parse(code)
      raise ArgumentError, "not a trump: #{code.inspect}" unless valid?(code)

      code == TRUMFLOES ? trumfloes : new(suit: code)
    end

    def initialize(suit:)
      raise ArgumentError, "not a suit: #{suit.inspect}" unless suit.nil? || Card::SUITS.include?(suit)

      super
    end

    def trumfloes? = suit.nil?
    def to_s = suit || TRUMFLOES
  end
end
