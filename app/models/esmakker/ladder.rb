module Esmakker
  # The one ranked list of every melding (REGLER §2.0 "Én meldstige"), in
  # Anders's order, lowest first:
  #
  #   8, 8+påhæng…, 9, 9+påhæng…, sol, 10, 10+påhæng…, ren sol,
  #   11, 11+påhæng…, bordlægger, 12, 12+påhæng…, ren bordlægger,
  #   13, 13+påhæng…
  #
  # Each sol melding sits right after the påhæng of the number below it
  # (the Whistklubben source in §2.8 puts sol between 9 and 9+; §2.0's
  # closing note and tickets 09/10 put it after 9+, which is Anders's;
  # assumption A8 in .scratch/esmakker/issues/02-meldingsrunde.md).
  #
  # The påhæng on one number follow the bord's påhæng order, given highest
  # first as the bord shows it ("vip > halve > gode"). A påhæng left out of
  # the order does not exist at the bord. v1 is strict: no two påhæng share
  # a tier.
  class Ladder
    DEFAULT_PAHAENG_ORDER = %i[vip halve gode].freeze
    SOL_AFTER = { 9 => :sol, 10 => :ren_sol, 11 => :bordlaegger, 12 => :ren_bordlaegger }.freeze

    attr_reader :pahaeng_order, :meldinger

    def self.standard = new

    # pahaeng_order: highest first; symbols or strings. Raises ArgumentError
    # on an unknown or repeated påhæng.
    def initialize(pahaeng_order: DEFAULT_PAHAENG_ORDER)
      order = pahaeng_order.map(&:to_sym)
      raise ArgumentError, "unknown påhæng in #{pahaeng_order.inspect}" unless (order - Melding::PAHAENG).empty?
      raise ArgumentError, "a påhæng appears twice in #{pahaeng_order.inspect}" unless order.uniq == order

      @pahaeng_order = order.freeze
      @meldinger = build.freeze
      @ranks = @meldinger.each_with_index.to_h.freeze
      freeze
    end

    def include?(melding) = @ranks.key?(melding)
    def lowest = meldinger.first
    def highest = meldinger.last

    # Position on the ladder, 0 for the lowest. Raises ArgumentError for a
    # melding the bord does not have (e.g. a påhæng left out).
    def rank(melding)
      @ranks.fetch(melding) { raise ArgumentError, "not on this ladder: #{melding}" }
    end

    # -1, 0 or 1, like <=>.
    def compare(one, other) = rank(one) <=> rank(other)
    def higher?(one, other) = compare(one, other).positive?

    # Every melding strictly above the given one, lowest first; the whole
    # ladder for nil (nothing bid yet). These are the legal bids over it.
    def above(melding)
      return meldinger if melding.nil?

      meldinger.drop(rank(melding) + 1)
    end

    private

    def build
      Melding::NUMBERS.flat_map do |number|
        stik = [ Melding.stik(number), *pahaeng_order.reverse.map { |pahaeng| Melding.stik(number, pahaeng) } ]
        sol_melding = SOL_AFTER[number]
        sol_melding ? [ *stik, Melding.sol_melding(sol_melding) ] : stik
      end
    end
  end
end
