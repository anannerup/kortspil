# The live state of a spil in progress, rebuilt from its rows once per
# table command (see the spec's Persistence section): the game row and its
# current round row, the engine's runde and spil built from them, and the
# bord's seating. TableCommands loads one under the game's lock, asks it
# what is due, and saves passes, plays and deals through it.
#
# Names: `game` and `round` are the ActiveRecord rows (::Game, ::Round), as
# everywhere in Rails code. The engine's values built from them are
# `engine_round` (Hjerterfri::Round) and `engine_game` (Hjerterfri::Game),
# as in Round#to_engine and Game#engine_rules.
#
# Each stored runde is replayed once, when the spil is loaded. A LiveGame
# does not change: #apply and #deal_next return the next one. The rows it
# was built from are updated in place, so the old LiveGame is spent.
class LiveGame
  SEAT_COUNT = Hjerterfri::Deal::SEAT_COUNT
  # Versions per runde: four passes, 52 plays, a moon choice, and one step
  # for the deal, so the first state of a runde is newer than the last of
  # the one before.
  STEPS_PER_RUNDE = SEAT_COUNT + (SEAT_COUNT * Hjerterfri::Deal::HAND_SIZE) + 1 + 1

  # The result of #apply: the next LiveGame, or the reason the intent was
  # rejected (with this LiveGame unchanged).
  Step = Data.define(:live, :reason) do
    def rejected? = !reason.nil?
  end

  attr_reader :game, :engine_round, :engine_game, :seating

  # A new spil at the table with whoever sits there now; runde 1 is dealt.
  def self.start(table:, rules:, shuffler:)
    seating = table.seating
    game = table.games.create!(rules: rules.to_h, seats: seating.snapshot)
    new(game:, round: game.rounds.deal!(1, shuffler:), seating:, earlier_results: [])
  end

  def self.load(game)
    rules = game.engine_rules
    *earlier, round = game.rounds.reload.to_a
    earlier_results = earlier.map { |row| row.to_engine(rules) }.select(&:complete?).map(&:points)
    new(game:, round:, seating: game.table.seating, earlier_results:)
  end

  # Loads the spil under the game's row lock, so commands for one spil run
  # one at a time, and returns what the block returns.
  def self.locked(game) = game.with_lock { yield load(game) }

  def initialize(game:, round:, seating:, earlier_results:, engine_round: round.to_engine(game.engine_rules))
    @game = game
    @round = round
    @seating = seating
    @earlier_results = earlier_results
    @engine_round = engine_round
    results = engine_round.complete? ? [ *earlier_results, engine_round.points ] : earlier_results
    @engine_game = Hjerterfri::Game.new(rules: engine_round.rules, results:)
  end

  def in_progress? = game.in_progress?

  # Grows with every pass, play, moon choice and deal in the spil, so
  # clients can ignore a state that arrives after a newer one, and a
  # scheduled bot turn can tell it is stale.
  def version
    runde_base + engine_round.passes.passed_seats.size + engine_round.plays.size + (engine_round.moon_choice ? 1 : 0)
  end

  # The bot seats that are to act now: in the pass every bot that has not
  # passed (they pass at the same time), in play the bot whose turn it is,
  # and a bot moon shooter that is to choose.
  def bots_to_act
    return [] unless in_progress?

    seats = engine_round.passing? ? (0...SEAT_COUNT).reject { |seat| engine_round.passes.passed?(seat) } : [ engine_round.to_act ].compact
    seats.select { |seat| seating.occupants.fetch(seat).bot? }
  end

  # Whether a bot turn scheduled at `scheduled_version` should still be
  # taken. A pass only needs the runde to be the one it was scheduled in; a
  # play needs nothing to have happened since.
  def bot_turn_due?(seat, scheduled_version)
    return false unless bots_to_act.include?(seat)

    engine_round.passing? ? scheduled_version >= runde_base : scheduled_version == version
  end

  # Applies a pass, play or moon choice for the seat and saves it. The
  # runde that completes the spil finishes it.
  def apply(seat, intent)
    result = engine_round.apply(seat, intent)
    return Step.new(live: self, reason: result.reason) if result.rejected?

    @round.update!(passes: result.round.passes_string, plays: result.round.plays_string, moon_choice: result.round.moon_choice)
    after = LiveGame.new(game:, round: @round, seating:, earlier_results: @earlier_results, engine_round: result.round)
    game.update!(status: :finished, final_scores: after.engine_game.totals) if after.engine_game.over?
    Step.new(live: after, reason: nil)
  end

  # The number of the runde to deal next: once this runde is complete and
  # the spil goes on. Otherwise nil.
  def next_runde_number = in_progress? && engine_round.complete? ? @round.number + 1 : nil

  def deal_next(shuffler:)
    number = next_runde_number
    raise ArgumentError, "no runde is due" unless number

    LiveGame.new(game:, round: game.rounds.deal!(number, shuffler:), seating:, earlier_results: engine_game.results)
  end

  # A player left the spil in progress: it is abandoned with the totals of
  # its completed runder and the leaver recorded, so it counts as their loss.
  def abandon!(forfeited_by:)
    game.update!(status: :abandoned, final_scores: engine_game.totals, forfeited_by:) if in_progress?
  end

  # Everything the seat may see, for the "state" message.
  def state_for(seat)
    {
      table_id: game.table_id,
      table_kind: game.table.kind,
      game_id: game.id,
      status: game.status,
      round_number: @round.number,
      version:,
      rules: engine_game.rules.to_h,
      seats: seating.occupants.map { |occupant| { seat: occupant.seat, name: occupant.name, bot: occupant.bot? } },
      view: engine_round.view_for(seat),
      points_taken: engine_round.points_taken,
      score:,
      play_again_seats: game.play_again_seats(seating)
    }
  end

  private

  def runde_base = (@round.number - 1) * STEPS_PER_RUNDE

  # The score sheet: completed runder with running totals, who leads (the
  # lowest total) and, once the spil is over, who won.
  def score
    totals = engine_game.totals
    leaders = engine_game.results.empty? ? [] : totals.each_index.select { |seat| totals[seat] == totals.min }
    { end_score: engine_game.rules.end_score, rows: engine_game.rows, totals:, leaders:, winners: engine_game.winners }
  end
end
