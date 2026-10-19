require "test_helper"

# The spil in progress as one loaded object: rebuilt from rows equals the
# live state, versions only grow, each runde is replayed once per load, and
# bot turns are due only while nothing has moved on.
class LiveGameTest < ActiveSupport::TestCase
  setup do
    @user = users(:approved)
    table = Table.create!(host: @user, kind: :practice, status: :playing)
    table.seating.seat_practice!(@user)
    @live = LiveGame.start(table:, rules: Hjerterfri::Rules.new(end_score: 1000), shuffler: Random.new(0))
  end

  test "a started spil stores who sat where and deals runde 1" do
    assert_equal @live.seating.snapshot, @live.game.seats
    assert_equal [ 1 ], @live.game.rounds.map(&:number)
    assert_equal :passing, @live.engine_round.phase
    assert_equal [ 1, 2, 3 ], @live.bots_to_act
  end

  test "rebuilding from the database gives the same state, mid-pass, mid-play and in a later runde" do
    live = step(@live, 2)
    assert_rebuilds live

    live = step(live, 4 + 10)
    assert_equal :playing, live.engine_round.phase
    assert_rebuilds live

    live = play_out(live).deal_next(shuffler: Random.new(1))
    live = step(live, 5)
    assert_rebuilds live
    assert_equal [ 1 ], live.engine_game.rows.map { |row| row[:number] }
  end

  test "the version grows by one with every pass and play and with every deal" do
    versions = [ @live.version ]
    live = play_out(@live) { |after| versions << after.version }
    versions << live.deal_next(shuffler: Random.new(1)).version

    assert_equal versions.sort, versions
    assert_equal versions.size, versions.uniq.size
    assert_equal 4 + 52, versions[-2] - versions.first, "four passes and 52 plays"
  end

  test "loading replays each stored runde once, and building the state for every seat replays nothing more" do
    live = play_out(@live).deal_next(shuffler: Random.new(1))
    live = play_out(live).deal_next(shuffler: Random.new(2))
    step(live, 3)

    replays = count_replays do
      loaded = LiveGame.load(@live.game)
      (0..3).each { |seat| loaded.state_for(seat) }
      loaded.engine_game.totals
    end

    assert_equal 3, replays
  end

  test "a whole table command replays each stored runde once" do
    live = play_out(@live).deal_next(shuffler: Random.new(1))
    hand = live.engine_round.view_for(0)[:hand]

    replays = count_replays do
      TableCommands.new(scheduler: Class.new { def self.bot_turn(**) = nil }).pass(table: live.game.table, user: @user, cards: hand.last(3))
    end

    assert_equal 2, replays
  end

  test "an illegal intent is rejected with its reason and nothing is saved" do
    hand = @live.engine_round.view_for(0)[:hand]

    step = @live.apply(0, Hjerterfri::Pass.new(cards: hand.first(2)))

    assert step.rejected?
    assert_equal :wrong_card_count, step.reason
    assert_same @live, step.live
    assert_equal "", @live.game.current_round.reload.passes
  end

  test "a bot's pass is due until it has passed, and only in the runde it was scheduled in" do
    scheduled = @live.version
    assert @live.bot_turn_due?(1, scheduled)
    assert_not @live.bot_turn_due?(0, scheduled), "seat 0 is the human's"

    passed = pass_for(@live, 1)
    assert_not passed.bot_turn_due?(1, scheduled)
    assert passed.bot_turn_due?(2, scheduled), "bots pass at the same time"

    later = play_out(passed).deal_next(shuffler: Random.new(1))
    assert_not later.bot_turn_due?(2, scheduled), "scheduled in the runde before"
    assert later.bot_turn_due?(2, later.version)
  end

  test "a bot's play is due only while nothing has happened since it was scheduled" do
    live = @live
    live = play_one(live) until live.engine_round.phase == :playing && live.bots_to_act.any?
    seat = live.engine_round.to_act

    assert live.bot_turn_due?(seat, live.version)
    assert_not live.bot_turn_due?(seat, live.version - 1)
    assert_not play_one(live).bot_turn_due?(seat, live.version)
  end

  test "the next runde is due once the runde is complete; the runde that ends the spil finishes it" do
    assert_nil @live.next_runde_number
    assert_raises(ArgumentError) { @live.deal_next(shuffler: Random.new(1)) }
    assert_equal 2, play_out(@live).next_runde_number
    assert @live.game.reload.in_progress?

    table = @live.game.table
    table.games.last.update!(status: :finished)
    done = play_out(LiveGame.start(table:, rules: Hjerterfri::Rules.new(end_score: 1), shuffler: Random.new(0)))
    assert done.game.reload.finished?
    assert_equal done.engine_game.totals, done.game.final_scores
    assert_nil done.next_runde_number
    assert_empty done.bots_to_act
  end

  test "abandoning keeps the totals of completed runder and records the leaver" do
    live = step(play_out(@live).deal_next(shuffler: Random.new(1)), 2)
    totals = live.engine_game.totals

    live.abandon!(forfeited_by: @user)

    game = live.game.reload
    assert game.abandoned?
    assert_equal [ totals, @user ], [ game.final_scores, game.forfeited_by ]
    assert_empty LiveGame.load(game).bots_to_act
  end

  private

  def assert_rebuilds(live)
    rebuilt = LiveGame.load(Game.find(live.game.id))
    (0..3).each { |seat| assert_equal live.state_for(seat).as_json, rebuilt.state_for(seat).as_json }
  end

  # Applies `count` passes or plays, each by the first seat due.
  def step(live, count)
    count.times { live = play_one(live) }
    live
  end

  # Plays the runde out. Yields each LiveGame after a step.
  def play_out(live)
    until live.engine_round.complete?
      live = play_one(live)
      yield live if block_given?
    end
    live
  end

  def play_one(live)
    round = live.engine_round
    return pass_for(live, (0..3).find { |seat| !round.passes.passed?(seat) }) if round.passing?

    apply!(live, round.to_act, Hjerterfri::Play.new(card: round.legal_moves(round.to_act).first))
  end

  def pass_for(live, seat) = apply!(live, seat, Hjerterfri::Pass.new(cards: live.engine_round.view_for(seat)[:hand].last(3)))

  def apply!(live, seat, intent)
    result = live.apply(seat, intent)
    raise "rejected: #{result.reason}" if result.rejected?

    result.live
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
