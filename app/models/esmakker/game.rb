module Esmakker
  # One es-makker spil: a fixed number of runder (the bord's TableRules),
  # and the runde results so far. Immutable and built from data.
  #
  # Results are the completed runder's results (RundeResult, Round#result),
  # in order; a runde dealt again is no result. Each holds its points per
  # seat (Scoring); the totals are their running sum from 0, zero-sum.
  # Points are won, so the highest total leads.
  class Game < Data.define(:rules, :runder, :results)
    def initialize(rules:, runder:, results: [])
      raise ArgumentError, "a spil is a positive number of runder" unless runder.is_a?(Integer) && runder.positive?

      super(rules:, runder:, results: results.dup.freeze)
    end

    def totals = Scoring.sum(results.map(&:points))

    # The totals after each runde, in order.
    def running_totals = results.each_index.map { |index| Scoring.sum(results.first(index + 1).map(&:points)) }

    # The seats with the highest total; none before the first runde.
    def leaders
      return [] if results.empty?

      best = totals.max
      totals.each_index.select { |seat| totals[seat] == best }
    end

    # Over once every runde is played.
    def over? = results.size >= runder

    def next_runde_number = over? ? nil : results.size + 1
  end
end
