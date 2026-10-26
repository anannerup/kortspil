module Esmakker
  # The bord's point values (REGLER §2.0 "Point"), which the vært may
  # change. Es-makker is zero-sum; these are the amounts a runde is settled
  # with:
  #
  # - stakes: the stake per number, "8" => 1 … "13" => 3.5.
  # - pahaeng: the factor of a melding with påhæng (gode, halve).
  # - trumflos: the factor when the melder chose trumfløs.
  # - klor: the factor when clubs is trump at vip or halve (Anders, 26
  #   October 2026); not at an ordinary melding, where clubs could have been
  #   bid as gode, nor at gode, whose påhæng is clubs.
  # - vip_first/vip_second/vip_third: the factor of vip by the kitty card
  #   the melder took as trump (vip itself doubles nothing beyond it).
  # - bank: the factor of each bank.
  # - sol, ren_sol, bordlaegger, ren_bordlaegger: the fixed amount per
  #   modspiller (inferred values, REGLER §2.0, marked 🔶).
  #
  # Amounts may be halves (1.5); whole ones are kept as integers. Stored as
  # a plain hash (#to_h) inside the rules.
  class Points < Data.define(:stakes, :pahaeng, :trumflos, :klor, :vip_first, :vip_second, :vip_third, :bank, :sol, :ren_sol, :bordlaegger, :ren_bordlaegger)
    NUMBERS = %w[8 9 10 11 12 13].freeze
    STANDARD_STAKES = { "8" => 1, "9" => 1.5, "10" => 2, "11" => 2.5, "12" => 3, "13" => 3.5 }.freeze
    FACTORS = %i[pahaeng trumflos klor vip_first vip_second vip_third bank].freeze
    AMOUNTS = %i[sol ren_sol bordlaegger ren_bordlaegger].freeze

    def self.standard = new

    # Accepts symbol or string keys; missing keys take the standard value
    # (stakes too, number by number). Raises ArgumentError on unknown keys
    # or values that are not positive amounts.
    def self.from_h(hash)
      values = hash.to_h.transform_keys(&:to_sym)
      values[:stakes] = STANDARD_STAKES.merge(values[:stakes].to_h.transform_keys(&:to_s)) if values.key?(:stakes)
      new(**values)
    end

    # For stored snapshots: keys this version does not know are dropped.
    def self.from_stored(hash)
      values = hash.to_h.transform_keys(&:to_sym).slice(*members)
      values[:stakes] = values[:stakes].to_h.transform_keys(&:to_s).slice(*NUMBERS) if values.key?(:stakes)
      from_h(values)
    end

    # The amount in a form field ("1,5" or "1.5"), or nil when it is not a
    # positive amount.
    def self.amount(value)
      number = Float(value.to_s.strip.tr(",", "."), exception: false)
      number&.finite? && number.positive? ? number : nil
    end

    def initialize(stakes: STANDARD_STAKES, pahaeng: 2, trumflos: 2, klor: 2, vip_first: 2, vip_second: 4, vip_third: 8, bank: 2,
                   sol: 3, ren_sol: 4, bordlaegger: 5, ren_bordlaegger: 6)
      raise ArgumentError, "stakes are one per number #{NUMBERS.join(', ')}" unless stakes.is_a?(Hash) && stakes.keys.map(&:to_s).sort == NUMBERS.sort

      amounts = { pahaeng:, trumflos:, klor:, vip_first:, vip_second:, vip_third:, bank:, sol:, ren_sol:, bordlaegger:, ren_bordlaegger: }
      super(stakes: NUMBERS.to_h { |number| [ number, tidy(stakes[number] || stakes[number.to_sym]) ] }.freeze, **amounts.transform_values { |value| tidy(value) })
    end

    private

    def tidy(value)
      raise ArgumentError, "an amount is a positive number, not #{value.inspect}" unless value.is_a?(Numeric) && value.finite? && value.positive?

      value.to_f == value.to_i ? value.to_i : value.to_f
    end
  end
end
