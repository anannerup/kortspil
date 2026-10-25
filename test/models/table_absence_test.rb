require "test_helper"

# Seam 2 for absence and leaving (tickets 18 and 19): heartbeats, frakoblet,
# the turn timer, "Forlad bordet", bot takeover with the seat_log, the
# result and the last human leaving. Driven through TableCommands with an
# injected clock (FakeClock) and a FakeScheduler, so ticks run by hand and
# nothing sleeps. Asserted on outcomes, stored rows and the state sent.
class TableAbsenceTest < ActiveSupport::TestCase
  setup do
    @host = users(:approved)
    @players = [ @host, users(:admin), users(:erik), users(:frida) ]
    @scheduler = FakeScheduler.new
    @clock = FakeClock.new
  end

  # --- Keep-alive (18) ---

  test "heartbeats keep a seat connected; about 10 s of silence makes it frakoblet from its last heartbeat" do
    table = started_table
    erik = users(:erik)

    pass_time(table, 8, silent: [ erik ])
    assert_empty tick(table).messages, "8 s of silence is not yet lost"

    pass_time(table, 2, silent: [ erik ])
    outcome = tick(table)

    assert_equal (@players - [ erik ]).map(&:id).sort, outcome.messages.map(&:user_id).sort - [ erik.id ]
    seat = seat_info(outcome, @host, 2)
    assert seat["frakoblet"]
    assert_in_delta 50, seat["seconds_left"], 0.01, "the 60 s run from the last heartbeat"
    assert_equal erik, table.reload.seating.occupants[2].then { |occupant| User.find(occupant.user_id) }
  end

  test "a closed connection is frakoblet at once and the others see the countdown; a heartbeat keeps nobody else away" do
    table = started_table

    outcome = commands.disconnect(table:, user: users(:erik))

    assert_equal [ @host, users(:admin), users(:frida) ].map(&:id), outcome.messages.map(&:user_id)
    seat = seat_info(outcome, @host, 2)
    assert_equal [ true, 60.0 ], seat.values_at("frakoblet", "seconds_left")
    assert_not seat_info(outcome, @host, 1)["frakoblet"]
    assert_in_delta 10, @scheduler.ticks.last[:delay], 0.01, "the next check is still the others' heartbeats, before the 60 s"
  end

  test "a frakoblet player back at 59 s keeps their seat; the clock is cancelled and the others are told" do
    table = started_table
    erik = users(:erik)
    commands.disconnect(table:, user: erik)
    pass_time(table, 59, silent: [ erik ])
    assert_empty forladt_in(tick(table))

    outcome = commands.connect(table:, user: erik)

    assert_equal @players.map(&:id), outcome.messages.map(&:user_id)
    assert_not seat_info(outcome, @host, 2)["frakoblet"]
    pass_time(table, 5)
    assert_not_includes forladt_in(tick(table)), erik.id
    assert table.seated?(erik)
    assert_not_includes table.current_game.reload.seat_log.map { |entry| entry["from"] }, erik.id
  end

  test "a frakoblet player not back at 60 s has forladt: a bot takes the seat, even when it is not their turn" do
    table = started_table
    pass_all(table)
    leader = live(table).engine_round.to_act
    seat = (leader + 2) % 4
    player = @players[seat]
    commands.disconnect(table:, user: player)
    pass_time(table, 30, silent: [ player ])
    commands.play(table:, user: @players[leader], card: "2C")
    pass_time(table, 29, silent: [ player ])
    assert_empty forladt_in(tick(table))

    pass_time(table, 1, silent: [ player ])
    outcome = tick(table)

    assert_equal [ { "type" => "forladt" } ], outcome.messages.select { |message| message.user_id == player.id }.map(&:payload)
    occupant = table.reload.seating.occupants[seat]
    assert occupant.bot?
    assert_not table.seated?(player)
    assert_equal [ { "seat" => seat, "from" => player.id, "to" => occupant.name } ], table.current_game.reload.seat_log.map { |entry| entry.except("at_play") }
    assert_equal "2C", table.current_game.current_round.reload.plays, "not its turn, so the bot waits"
  end

  test "while a frakoblet seat is not to act the spil goes on; on its turn it waits only for the time that remains" do
    table = started_table
    pass_all(table)
    leader = live(table).engine_round.to_act
    away = (leader + 1) % 4
    commands.disconnect(table:, user: @players[away])

    pass_time(table, 10, silent: [ @players[away] ])
    commands.play(table:, user: @players[leader], card: "2C")

    assert_equal away, live(table).engine_round.to_act
    state = live(table).state_for(leader, now: @clock.now).as_json
    assert_in_delta 50, state["seats"][away]["seconds_left"], 0.01
    assert_nil state["seats"][leader]["seconds_left"], "no clock for a connected seat that is not to act"

    pass_time(table, 50, silent: [ @players[away] ])
    tick(table)

    assert table.seating.occupants[away].bot?
    assert_equal 2, table.current_game.current_round.reload.plays.split.size, "the bot played at once"
  end

  # --- Turn timer (18) ---

  test "a player inactive on their turn is warned at 30 s, not at 29, and has forladt at 60 s" do
    table = started_table
    pass_all(table)
    seat = live(table).engine_round.to_act
    player = @players[seat]

    pass_time(table, 29)
    assert_empty warnings_in(tick(table))

    pass_time(table, 1)
    outcome = tick(table)
    assert_equal [ [ player.id, { "type" => "turn_warning", "seconds_left" => 30.0 } ] ], warnings_in(outcome).map { |message| [ message.user_id, message.payload ] }
    assert_empty warnings_in(tick(table)), "warned once per turn"
    assert table.seated?(player)

    pass_time(table, 30)
    outcome = tick(table)

    assert_equal [ player.id ], forladt_in(outcome)
    assert table.seating.occupants[seat].bot?
    assert_equal "2C", table.current_game.current_round.reload.plays, "the bot led 2♣ at once"
  end

  test "each turn has its own clock, from when it began" do
    table = started_table
    pass_all(table)
    leader = live(table).engine_round.to_act

    pass_time(table, 45)
    commands.play(table:, user: @players[leader], card: "2C")
    pass_time(table, 29)

    assert_empty warnings_in(tick(table))
    assert_in_delta 31, live(table).turn_clock.seconds_left((leader + 1) % 4, @clock.now), 0.01
  end

  test "the pass is timed from the deal for every seat that has not passed" do
    table = started_table
    commands.pass(table:, user: @host, cards: hand(table, 0).last(3))

    pass_time(table, 30)
    outcome = tick(table)

    assert_equal @players.drop(1).map(&:id), warnings_in(outcome).map(&:user_id)
  end

  test "bots are exempt, and a practice table has no clock at all" do
    practice = started_practice(users(:erik), commands:)
    commands.disconnect(table: practice, user: users(:erik))
    @clock.advance(600)

    assert_empty commands.tick(game_id: practice.current_game.id).messages
    assert_empty @scheduler.ticks
    assert practice.reload.seated?(users(:erik))
    commands.leave(table: practice, user: users(:erik))

    table = started_table
    commands.leave(table:, user: users(:frida))
    pass_time(table, 600)
    assert_nil live(table).state_for(0, now: @clock.now)[:seats][3][:seconds_left]
  end

  test "ticks are scheduled for the next thing due, one chain per spil" do
    table = started_table
    assert_in_delta 10, @scheduler.ticks.last[:delay], 0.01, "a heartbeat timing out"
    count = @scheduler.ticks.size

    commands.connect(table:, user: @host)
    assert_equal count, @scheduler.ticks.size, "an earlier tick is already coming"
  end

  # --- Leaving (19) ---

  test "Forlad bordet on your turn: a bot takes the seat and plays at once; seat_log, name and totals" do
    table = started_table
    pass_all(table)
    seat = live(table).engine_round.to_act
    leaver = @players[seat]
    version = live(table).version
    totals = live(table).engine_game.totals

    outcome = commands.leave(table:, user: leaver)

    assert_equal [ { "type" => "forladt" } ], outcome.messages.select { |message| message.user_id == leaver.id }.map(&:payload)
    game = table.current_game.reload
    bot = table.reload.seating.occupants[seat]
    assert_equal [ { "seat" => seat, "from" => leaver.id, "to" => bot.name, "at_play" => version } ], game.seat_log
    assert_equal "2C", game.current_round.reload.plays
    info = seat_info(outcome, @players[(seat + 1) % 4], seat)
    assert_equal [ bot.name, true, leaver.username ], info.values_at("name", "bot", "took_over_from")
    assert_equal totals, live(table).engine_game.totals, "the seat keeps its running totals"
    assert game.in_progress?
    assert table.playing?
    assert_nil leaver.current_table
  end

  test "Forlad bordet during the pass: the bot passes at once" do
    table = started_table

    commands.leave(table:, user: users(:erik))

    assert live(table).engine_round.passes.passed?(2)
  end

  test "a player who has forladt cannot return to that spil, but may sit at another bord" do
    table = started_table
    erik = users(:erik)
    commands.leave(table:, user: erik)

    assert_empty commands.connect(table:, user: erik).messages
    assert_empty commands.heartbeat(table:, user: erik).messages
    assert_equal :not_waiting, commands.sit(table:, user: erik, seat: 2).refusal
    assert_includes table.current_game.reload.forladt_ids, erik.id
    assert_not commands.create_table(user: erik).refused?
  end

  test "when the vært forlader, the next human in seat order becomes vært" do
    table = started_table

    commands.leave(table:, user: @host)

    assert_equal users(:admin), table.reload.host
  end

  test "when the last human forlader, the spil is afbrudt and the bord closes; every leaver lost" do
    table = started_table
    @players.drop(1).each { |player| commands.leave(table:, user: player) }
    assert table.reload.playing?

    outcome = commands.leave(table:, user: @host)

    game = table.current_game.reload
    assert game.abandoned?
    assert table.reload.closed?
    assert_equal @host, game.forfeited_by
    assert_equal @players.map(&:id).sort, game.forladt_ids.sort
    assert_empty game.winner_ids
    assert_equal [ [ @host.id, { "type" => "closed" } ] ], outcome.messages.map { |message| [ message.user_id, message.payload ] }
  end

  test "the last human playing on against the bots forlader passively too: afbrudt" do
    table = started_table
    @players.drop(1).each { |player| commands.leave(table:, user: player) }
    commands.disconnect(table:, user: @host)

    @clock.advance(60)
    tick(table)

    assert table.current_game.reload.abandoned?
    assert table.reload.closed?
  end

  test "leaving after the spil is finished is standing up: no loss, and the others wait for the next spil in the lobby" do
    table = started_table(rules: Hjerterfri::Rules.new(end_score: 1))
    play_out(table)
    game = table.current_game.reload
    assert game.finished?

    outcome = commands.leave(table:, user: users(:erik))

    assert_empty game.reload.forladt_ids
    assert table.reload.closed?
    waiting = @host.current_table
    assert_not waiting.seated?(users(:erik))
    assert_equal [ [ users(:erik).id, "closed" ], *[ @host, users(:admin), users(:frida) ].map { |player| [ player.id, "waiting" ] } ],
      outcome.messages.map { |message| [ message.user_id, message.payload["type"] ] }
    assert_not commands.sit(table: waiting, user: users(:erik), seat: 2).refused?, "a free seat for the next spil"
  end

  test "a disconnect after the spil is over starts no clock" do
    table = started_table(rules: Hjerterfri::Rules.new(end_score: 1))
    play_out(table)

    assert_empty commands.disconnect(table:, user: users(:erik)).messages
    assert_not table.seating.occupants[2].frakoblet?
  end

  private

  def commands = TableCommands.new(scheduler: @scheduler, shuffler: Random.new(0), random: Random.new(0), clock: @clock)

  # An open table with the four players, started, every client connected.
  def started_table(rules: Hjerterfri::Rules.standard)
    table = commands.create_table(user: @host, rules:).table
    @players.drop(1).each.with_index(1) { |player, seat| commands.sit(table:, user: player, seat:) }
    table = commands.start(table:, user: @host).table
    @players.each { |player| commands.connect(table:, user: player) }
    table.reload
  end

  def tick(table) = commands.tick(game_id: table.current_game.id)

  # Lets `seconds` pass, every client but the silent ones sending a
  # heartbeat every 4 s.
  def pass_time(table, seconds, silent: [])
    remaining = seconds
    while remaining.positive?
      step = [ 4, remaining ].min
      @clock.advance(step)
      remaining -= step
      (@players - silent).each { |player| commands.heartbeat(table:, user: player) }
    end
  end

  def live(table) = LiveGame.load(table.current_game.reload)

  def hand(table, seat) = live(table).engine_round.view_for(seat)[:hand]

  def pass_all(table)
    @players.each_with_index { |player, seat| commands.pass(table:, user: player, cards: hand(table, seat).last(3)) }
  end

  # Plays the runde out: everyone passes, then whoever is to act plays
  # their first legal card, until the runde is complete.
  def play_out(table)
    pass_all(table)
    while (seat = live(table).engine_round.to_act)
      commands.play(table:, user: @players[seat], card: live(table).engine_round.legal_moves(seat).first)
    end
  end

  def seat_info(outcome, user, seat)
    outcome.messages.find { |message| message.user_id == user.id && message.payload["type"] == "state" }.payload["state"]["seats"][seat]
  end

  def warnings_in(outcome) = outcome.messages.select { |message| message.payload["type"] == "turn_warning" }

  def forladt_in(outcome) = outcome.messages.select { |message| message.payload["type"] == "forladt" }.map(&:user_id)
end
