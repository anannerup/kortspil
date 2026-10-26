require "test_helper"

# The spil gives its engine state itself: rebuilt from rows equals the
# state built up step by step, versions only grow, each runde is replayed
# once per load, and bot turns are due only while nothing has moved on.
class GameEngineStateTest < ActiveSupport::TestCase
  setup do
    @user = users(:approved)
    table = Table.create!(host: @user, kind: :practice, status: :playing)
    seat_practice!(table, @user)
    @game = Game.start!(table:, rules: Hjerterfri::Rules.new(end_score: 1000), shuffler: Random.new(0))
  end

  test "a started spil stores who sat where and deals runde 1" do
    assert_equal @game.seating.snapshot, @game.seats
    assert_equal [ 1 ], @game.rounds.map(&:number)
    assert_equal :passing, @game.engine_round.phase
    assert_equal [ 1, 2, 3 ], @game.bots_to_act
  end

  test "rebuilding from the database gives the same state, mid-pass, mid-play and in a later runde" do
    step(@game, 2)
    assert_rebuilds @game

    step(@game, 4 + 10)
    assert_equal :playing, @game.engine_round.phase
    assert_rebuilds @game

    play_out(@game).deal_next!(shuffler: Random.new(1))
    step(@game, 5)
    assert_rebuilds @game
    assert_equal [ 1 ], @game.engine_game.rows.map { |row| row[:number] }
  end

  test "the version grows by one with every pass and play and with every deal" do
    versions = [ @game.version ]
    play_out(@game) { |after| versions << after.version }
    @game.deal_next!(shuffler: Random.new(1))
    versions << @game.version

    assert_equal versions.sort, versions
    assert_equal versions.size, versions.uniq.size
    assert_equal 4 + 52, versions[-2] - versions.first, "four passes and 52 plays"
  end

  test "loading replays each stored runde once, and building the state for every seat replays nothing more" do
    play_out(@game).deal_next!(shuffler: Random.new(1))
    play_out(@game).deal_next!(shuffler: Random.new(2))
    step(@game, 3)

    replays = count_replays do
      loaded = Game.find(@game.id)
      (0..3).each { |seat| loaded.state_for(seat, now: Time.current) }
      loaded.engine_game.totals
    end

    assert_equal 3, replays
  end

  test "a whole action at the bord replays each stored runde once" do
    play_out(@game).deal_next!(shuffler: Random.new(1))
    hand = @game.engine_round.view_for(0)[:hand]

    replays = count_replays do
      player_acts(@game.table, :pass, player: @user, cards: hand.last(3), surroundings: Table::Surroundings.new(scheduler: Class.new { def self.bot_turn(**) = nil }))
    end

    assert_equal 2, replays
  end

  test "an illegal intent is rejected with its reason and nothing is saved" do
    hand = @game.engine_round.view_for(0)[:hand]
    before = @game.engine_round

    result = @game.apply(0, Hjerterfri::Pass.new(cards: hand.first(2)))

    assert result.rejected?
    assert_equal :wrong_card_count, result.reason
    assert_same before, @game.engine_round
    assert_equal "", @game.current_round.reload.passes
  end

  test "a bot's pass is due until it has passed, and only in the runde it was scheduled in" do
    scheduled = @game.version
    assert @game.bot_turn_due?(1, scheduled)
    assert_not @game.bot_turn_due?(0, scheduled), "seat 0 is the human's"

    pass_for(@game, 1)
    assert_not @game.bot_turn_due?(1, scheduled)
    assert @game.bot_turn_due?(2, scheduled), "bots pass at the same time"

    play_out(@game).deal_next!(shuffler: Random.new(1))
    assert_not @game.bot_turn_due?(2, scheduled), "scheduled in the runde before"
    assert @game.bot_turn_due?(2, @game.version)
  end

  test "a bot's play is due only while nothing has happened since it was scheduled" do
    play_one(@game) until @game.engine_round.phase == :playing && @game.bots_to_act.any?
    seat = @game.engine_round.to_act
    version = @game.version

    assert @game.bot_turn_due?(seat, version)
    assert_not @game.bot_turn_due?(seat, version - 1)
    assert_not play_one(@game).bot_turn_due?(seat, version)
  end

  test "the next runde is due once the runde is complete; the runde that ends the spil finishes it" do
    assert_nil @game.next_runde_number
    assert_raises(ArgumentError) { @game.deal_next!(shuffler: Random.new(1)) }
    assert_equal 2, play_out(@game).next_runde_number
    assert @game.reload.in_progress?

    table = @game.table
    table.games.last.update!(status: :finished)
    done = play_out(Game.start!(table:, rules: Hjerterfri::Rules.new(end_score: 1), shuffler: Random.new(0)))
    totals = done.engine_game.totals
    assert done.reload.finished?
    assert_equal totals, done.final_scores
    assert_nil done.next_runde_number
    assert_empty done.bots_to_act
  end

  test "abandoning keeps the totals of completed runder and records the leaver" do
    play_out(@game).deal_next!(shuffler: Random.new(1))
    step(@game, 2)
    totals = @game.engine_game.totals

    @game.abandon!(forfeited_by: @user)

    game = @game.reload
    assert game.abandoned?
    assert_equal [ totals, @user ], [ game.final_scores, game.forfeited_by ]
    assert_empty Game.find(game.id).bots_to_act
  end

  private

  def assert_rebuilds(game)
    rebuilt = Game.find(game.id)
    (0..3).each { |seat| assert_equal game.state_for(seat, now: Time.current).as_json, rebuilt.state_for(seat, now: Time.current).as_json }
  end

  # Applies `count` passes or plays, each by the first seat due.
  def step(game, count)
    count.times { play_one(game) }
    game
  end

  # Plays the runde out. Yields the spil after each step.
  def play_out(game)
    until game.engine_round.complete?
      play_one(game)
      yield game if block_given?
    end
    game
  end

  def play_one(game)
    round = game.engine_round
    return pass_for(game, (0..3).find { |seat| !round.passes.passed?(seat) }) if round.passing?

    apply!(game, round.to_act, Hjerterfri::Play.new(card: round.legal_moves(round.to_act).first))
  end

  def pass_for(game, seat) = apply!(game, seat, Hjerterfri::Pass.new(cards: game.engine_round.view_for(seat)[:hand].last(3)))

  def apply!(game, seat, intent)
    result = game.apply(seat, intent)
    raise "rejected: #{result.reason}" if result.rejected?

    game
  end

  # How often a stored runde is rebuilt into the engine's Round while the
  # block runs.
  def count_replays
    original = Hjerterfri::Round.method(:from_strings)
    count = 0
    Hjerterfri::Round.define_singleton_method(:from_strings) do |**args|
      count += 1
      original.call(**args)
    end
    yield
    count
  ensure
    Hjerterfri::Round.define_singleton_method(:from_strings, original)
  end
end
