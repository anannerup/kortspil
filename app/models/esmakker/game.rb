module Esmakker
  # One es-makker spil: a fixed number of runder (the bord's TableRules),
  # and the runde results so far. Immutable and built from data.
  #
  # Results are the runde points per seat (Round#points), one array of four
  # per completed runde. Scoring comes in ticket 05; until then no runde
  # completes, and the totals stay 0.
  class Game < Data.define(:rules, :runder, :results)
    def initialize(rules:, runder:, results: [])
      raise ArgumentError, "a spil is a positive number of runder" unless runder.is_a?(Integer) && runder.positive?

      super(rules:, runder:, results: results.map { |points| points.dup.freeze }.freeze)
    end

    def totals = results.reduce([ 0 ] * SEAT_COUNT) { |sum, points| sum.zip(points).map(&:sum) }

    # Over once every runde is played.
    def over? = results.size >= runder

    def next_runde_number = over? ? nil : results.size + 1
  end
end
