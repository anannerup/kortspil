module Hjerterfri
  # One spil: the runde results so far, added up against the rules' end
  # score. Immutable and built from data: #add returns the next Game.
  #
  # Results are the runde points per seat (Round#points), one array of four
  # per completed runde, in runde order.
  class Game < Data.define(:rules, :results)
    def initialize(rules:, results: [])
      unless results.all? { |points| points.is_a?(Array) && points.size == Deal::SEAT_COUNT && points.all?(Integer) }
        raise ArgumentError, "each runde result is #{Deal::SEAT_COUNT} integer scores"
      end

      super(rules:, results: results.map { |points| points.dup.freeze }.freeze)
    end

    # Raises ArgumentError once the spil is over: no runde follows the last.
    def add(points)
      raise ArgumentError, "the spil is over" if over?

      Game.new(rules:, results: [ *results, points ])
    end

    def totals = results.reduce([ 0 ] * Deal::SEAT_COUNT) { |sum, points| add_up(sum, points) }

    # The score sheet: one row per runde with its points and running totals.
    def rows
      running = [ 0 ] * Deal::SEAT_COUNT
      results.each_with_index.map do |points, index|
        running = add_up(running, points)
        { number: index + 1, pass_direction: PassDirection.for_runde(index + 1), points:, totals: running }
      end
    end

    # Over once a seat has reached the end score after a completed runde.
    def over? = results.any? && totals.max >= rules.end_score

    # The seats with the lowest total once the spil is over; ties share the
    # win (inferred, see spec "Where the rules come from"). Empty until over.
    def winners
      return [] unless over?

      totals.each_index.select { |seat| totals[seat] == totals.min }
    end

    def next_runde_number = over? ? nil : results.size + 1
    def next_pass_direction = over? ? nil : PassDirection.for_runde(next_runde_number)

    private

    def add_up(left, right) = left.zip(right).map(&:sum)
  end
end
