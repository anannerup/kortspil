module Esmakker
  # One of the deck's three jokers (REGLER §2.0 "Jokere").
  class Joker < Data.define(:number)
    NUMBERS = (1..3)

    def self.valid?(code) = code.is_a?(String) && code.size == 2 && code[0] == "X" && NUMBERS.map(&:to_s).include?(code[1])

    def self.parse(code)
      raise ArgumentError, "not a joker code: #{code.inspect}" unless valid?(code)

      new(number: code[1].to_i)
    end

    def self.all = NUMBERS.map { |number| new(number:) }

    def to_s = "X#{number}"
    def joker? = true
    def fordaekt? = false
    def ace? = false
    def suit = nil
    def display_key = [ Card::DISPLAY_SUITS.size, number ]
  end
end
