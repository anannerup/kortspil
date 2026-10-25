module Hjerterfri
  # The bot tournament (spec §8). Two measures:
  # - #duplicate (the main one): every deal is played once per level and
  #   seat, each level holding the very same hand from the very same seat
  #   against the same field, so card luck and the opponents cancel out;
  # - #run (a side metric): seeded spil between bots of every level, with
  #   the levels rotated over the seats; average points per runde and wins.
  # Lower is better; the aim is Svær < Mellem < Let. The Rust botlab has the
  # same measures, much faster (tools/botlab/README.md).
  class Tournament
    # Four seats, three levels: each pattern seats one level twice, and
    # every pattern is rotated over the seats, so each level gets every
    # seat and every neighbour equally often.
    PATTERNS = Bot::LEVELS.flat_map do |twice|
      (0...Deal::SEAT_COUNT).map { |turn| [ *Bot::LEVELS, twice ].rotate(turn) }
    end.freeze

    Report = Data.define(:spil, :runder, :points_per_runde, :wins)

    # Per level: mean points per runde and its 95 % confidence half-width.
    # Per pair [stronger, weaker]: shares of hands it did better, the same
    # and worse with, and the mean difference with its half-width.
    DuplicateReport = Data.define(:deals, :field, :points, :pairs)

    def initialize(spil:, seed: 0, rules: Rules.standard)
      @spil = spil
      @seed = seed
      @rules = rules
    end

    def run
      totals = Hash.new(0)
      seats_played = Hash.new(0)
      wins = Hash.new(0)
      runder = 0

      @spil.times do |index|
        levels = PATTERNS[index % PATTERNS.size]
        game, played = play_spil(levels, seed: @seed * 100_000 + index)
        runder += played
        levels.each_with_index do |level, seat|
          totals[level] += game.totals[seat]
          seats_played[level] += played
        end
        game.winners.each { |seat| wins[levels[seat]] += 1 }
      end

      per_runde = Bot::LEVELS.to_h { |level| [ level, (totals[level].to_f / seats_played[level]).round(2) ] }
      Report.new(spil: @spil, runder:, points_per_runde: per_runde, wins: Bot::LEVELS.to_h { |level| [ level, wins[level] ] })
    end

    def duplicate(field: :mellem)
      results = (0...@spil).flat_map do |index|
        (0...Deal::SEAT_COUNT).map do |seat|
          Bot::LEVELS.to_h { |level| [ level, play_duplicate(index, seat, level, field) ] }
        end
      end
      points = Bot::LEVELS.to_h { |level| [ level, mean_ci(results.map { |r| r[level] }) ] }
      pairs = [ %i[svaer mellem], %i[mellem let], %i[svaer let] ].to_h do |a, b|
        diffs = results.map { |r| r[a] - r[b] }
        shares = [ diffs.count(&:negative?), diffs.count(&:zero?), diffs.count(&:positive?) ].map { |n| n.to_f / diffs.size }
        [ [ a, b ], { better: shares[0], same: shares[1], worse: shares[2], difference: mean_ci(diffs) } ]
      end
      DuplicateReport.new(deals: @spil, field:, points:, pairs:)
    end

    private

    # One runde of deal `index` with `level` in `seat` and the field
    # elsewhere; the deal, pass direction and variation seeds depend only on
    # the deal and the seat, never on the level.
    def play_duplicate(index, seat, level, field)
      deal_seed = @seed * 1_000_003 + index
      bots = (0...Deal::SEAT_COUNT).map { |s| Bot.new(level: s == seat ? level : field, random: Random.new(deal_seed * 4 + s)) }
      round = Round.new(rules: @rules, deal: Deal.shuffled(shuffler: Random.new(deal_seed)), pass_direction: PassDirection.for_runde(index % 4 + 1))
      play_round(round, bots, Array.new(Deal::SEAT_COUNT, 0)).points[seat]
    end

    def mean_ci(values)
      mean = values.sum.to_f / values.size
      variance = values.sum { |v| (v - mean)**2 } / [ values.size - 1, 1 ].max
      [ mean, 1.96 * Math.sqrt(variance / values.size) ]
    end

    def play_spil(levels, seed:)
      bots = levels.each_with_index.map { |level, seat| Bot.new(level:, random: Random.new(seed * 4 + seat)) }
      shuffler = Random.new(seed)
      game = Game.new(rules: @rules)
      played = 0

      until game.over?
        game = game.add(play_runde(game, bots, shuffler))
        played += 1
      end
      [ game, played ]
    end

    def play_runde(game, bots, shuffler)
      round = Round.new(rules: @rules, deal: Deal.shuffled(shuffler:), pass_direction: game.next_pass_direction)
      play_round(round, bots, game.totals).points
    end

    def play_round(round, bots, totals)
      (0...Deal::SEAT_COUNT).each { |seat| round = act(round, seat, Pass.new(cards: bots[seat].choose_pass(round.view_for(seat)))) } if round.passing?

      until round.complete?
        seat = round.to_act
        intent =
          if round.choosing_moon? then MoonChoice.new(option: bots[seat].choose_moon(seat:, totals:))
          else Play.new(card: bots[seat].choose_play(round.view_for(seat), totals:, end_score: @rules.end_score))
          end
        round = act(round, seat, intent)
      end
      round
    end

    def act(round, seat, intent)
      result = round.apply(seat, intent)
      raise "bot at seat #{seat} made an illegal move: #{result.reason}" unless result.accepted?

      result.round
    end
  end
end
