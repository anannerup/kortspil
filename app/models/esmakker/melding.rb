module Esmakker
  # One melding in the meldingsrunde (REGLER §2.0): a number of stik, 8–13,
  # with or without one påhæng (gode, halve, vip), or one of the four sol-melding
  # meldinger (sol, ren sol, bordlægger, ren bordlægger).
  #
  # There are no suit meldinger, no stærke and nothing below 8; trumfløs is
  # not a melding (the melder may choose it as trump after winning). Where a
  # melding ranks is the Ladder's business, not the melding's.
  #
  # Codes, e.g. for views and storage: "9", "9vip", "10gode", "sol",
  # "ren_sol", "bordlaegger", "ren_bordlaegger".
  class Melding < Data.define(:kind, :number, :pahaeng)
    NUMBERS = (8..13).freeze
    PAHAENG = %i[gode halve vip].freeze
    SOL_MELDINGER = %i[sol ren_sol bordlaegger ren_bordlaegger].freeze

    def self.stik(number, pahaeng = nil) = new(kind: :stik, number:, pahaeng:)
    def self.sol_melding(kind) = new(kind:, number: nil, pahaeng: nil)
    def self.sol = sol_melding(:sol)
    def self.ren_sol = sol_melding(:ren_sol)
    def self.bordlaegger = sol_melding(:bordlaegger)
    def self.ren_bordlaegger = sol_melding(:ren_bordlaegger)

    # Raises ArgumentError on a code that is not a melding.
    def self.parse(code)
      text = code.to_s
      return sol_melding(text.to_sym) if SOL_MELDINGER.map(&:to_s).include?(text)

      match = /\A(\d+)(#{PAHAENG.join("|")})?\z/.match(text)
      raise ArgumentError, "not a melding: #{code.inspect}" unless match

      stik(match[1].to_i, match[2]&.to_sym)
    end

    def initialize(kind:, number: nil, pahaeng: nil)
      if kind == :stik
        raise ArgumentError, "a melding is 8–13 stik: #{number.inspect}" unless NUMBERS.include?(number)
        raise ArgumentError, "not a påhæng: #{pahaeng.inspect}" unless pahaeng.nil? || PAHAENG.include?(pahaeng)
      else
        raise ArgumentError, "not a melding: #{kind.inspect}" unless SOL_MELDINGER.include?(kind)
        raise ArgumentError, "a sol melding has no number or påhæng" unless number.nil? && pahaeng.nil?
      end

      super
    end

    def stik? = kind == :stik
    def sol_melding? = !stik?
    def to_s = stik? ? "#{number}#{pahaeng}" : kind.to_s
  end
end
