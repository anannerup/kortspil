module Hjerterfri
  # The bot tournament (spec §8): seeded spil between bots of every level,
  # with the levels rotated over the seats, reporting the average points
  # per runde per level. Lower is better; the aim is Svær < Mellem < Let.
  class Tournament
    # Four seats, three levels: each pattern seats one level twice, and
    # every pattern is rotated over the seats, so each level gets every
    # seat and every neighbour equally often.
    PATTERNS = Bot::LEVELS.flat_map do |twice|
      (0...Deal::SEAT_COUNT).map { |turn| [ *Bot::LEVELS, twice ].rotate(turn) }
    end.freeze

    Report = Data.define(:spil, :runder, :points_per_runde, :wins)

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

    private

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
      (0...Deal::SEAT_COUNT).each { |seat| round = act(round, seat, Pass.new(cards: bots[seat].choose_pass(round.view_for(seat)))) } if round.passing?

      until round.complete?
        seat = round.to_act
        intent =
          if round.choosing_moon? then MoonChoice.new(option: bots[seat].choose_moon(seat:, totals: game.totals))
          else Play.new(card: bots[seat].choose_play(round.view_for(seat), totals: game.totals, end_score: @rules.end_score))
          end
        round = act(round, seat, intent)
      end
      round.points
    end

    def act(round, seat, intent)
      result = round.apply(seat, intent)
      raise "bot at seat #{seat} made an illegal move: #{result.reason}" unless result.accepted?

      result.round
    end
  end
end
