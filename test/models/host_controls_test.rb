require "test_helper"

# Seam 2 for host controls (ticket 13): kicking, adding and removing bots,
# changing the rules and the table type before the start, vært handover,
# auto-close, and "Spil igen" with the same players. Driven through
# TableCommands and asserted on its outcomes, the stored rows and what the
# lobby is sent.
class HostControlsTest < ActiveSupport::TestCase
  setup do
    @host = users(:approved)
    @erik = users(:erik)
    @frida = users(:frida)
    @scheduler = FakeScheduler.new
  end

  # --- Kick ---

  test "the vært kicks a player before the start, and the seat is free again" do
    table = create_table
    commands.sit(table:, user: @erik, seat: 2)

    outcome = commands.kick(table:, user: @host, seat: 2)

    assert_not outcome.refused?
    assert_not table.reload.seated?(@erik)
    assert table.seating.occupants.fetch(2).empty?
    assert_nil @erik.current_table
    assert_not commands.sit(table:, user: @erik, seat: 2).refused?, "a kick is not a ban"
  end

  test "only the vært may kick, only a human other than themself, and only before the start" do
    table = create_table
    commands.sit(table:, user: @erik, seat: 1)
    commands.add_bot(table:, user: @host, seat: 2)

    assert_equal :not_host, commands.kick(table:, user: @erik, seat: 0).refusal
    assert_equal :nobody_to_kick, commands.kick(table:, user: @host, seat: 0).refusal, "the vært stands up instead"
    assert_equal :nobody_to_kick, commands.kick(table:, user: @host, seat: 2).refusal, "a bot is removed, not kicked"
    assert_equal :nobody_to_kick, commands.kick(table:, user: @host, seat: 3).refusal
    assert_equal :no_such_seat, commands.kick(table:, user: @host, seat: 7).refusal
    assert table.reload.seated?(@erik)

    commands.add_bot(table:, user: @host, seat: 3)
    commands.start(table:, user: @host)
    assert_equal :not_waiting, commands.kick(table:, user: @host, seat: 1).refusal
    assert table.reload.seated?(@erik)
  end

  # --- Bots ---

  test "the vært puts bots in empty seats and removes them again; the lobby shows them" do
    table = create_table

    assert_not commands.add_bot(table:, user: @host, seat: 1).refused?
    assert_not commands.add_bot(table:, user: @host, seat: 3).refused?

    assert_equal [ @host.username, "Bot 1", nil, "Bot 2" ], table.seating.occupants.map(&:name)
    assert_equal [ false, true, false, true ], listed.sole["seats"].map { |seat| seat["bot"] }

    assert_not commands.remove_bot(table:, user: @host, seat: 1).refused?
    assert table.seating.occupants.fetch(1).empty?
    assert_equal :no_bot_there, commands.remove_bot(table:, user: @host, seat: 1).refusal
    assert_equal :no_bot_there, commands.remove_bot(table:, user: @host, seat: 0).refusal
  end

  test "only the vært adds or removes bots, only in a free seat, and only before the start" do
    table = create_table
    commands.sit(table:, user: @erik, seat: 1)

    assert_equal :not_host, commands.add_bot(table:, user: @erik, seat: 2).refusal
    assert_equal :seat_taken, commands.add_bot(table:, user: @host, seat: 1).refusal
    assert_equal :no_such_seat, commands.add_bot(table:, user: @host, seat: 4).refusal
    commands.add_bot(table:, user: @host, seat: 2)
    assert_equal :not_host, commands.remove_bot(table:, user: @erik, seat: 2).refusal

    commands.add_bot(table:, user: @host, seat: 3)
    commands.start(table:, user: @host)
    assert_equal :not_waiting, commands.remove_bot(table:, user: @host, seat: 2).refusal
    assert table.seating.occupants.fetch(2).bot?
  end

  test "a spil starts with bots in the empty seats, and the bots are scheduled to pass" do
    table = create_table
    commands.sit(table:, user: @erik, seat: 2)
    commands.add_bot(table:, user: @host, seat: 1)
    commands.add_bot(table:, user: @host, seat: 3)

    outcome = commands.start(table:, user: @host)

    assert_not outcome.refused?
    assert_equal [ { "kind" => "human", "user_id" => @host.id }, { "kind" => "bot", "name" => "Bot 1" },
                   { "kind" => "human", "user_id" => @erik.id }, { "kind" => "bot", "name" => "Bot 2" } ], table.current_game.seats
    assert_equal [ 1, 3 ], @scheduler.turns.map { |turn| turn[:seat] }
    assert_equal [ @host.id, @erik.id ], outcome.messages.map(&:user_id)
  end

  # --- Settings ---

  test "the vært changes the rules and the table type before the start" do
    table = create_table
    rules = Hjerterfri::Rules.new(end_score: 30, queen_breaks_hearts: true)

    outcome = commands.change_settings(table:, user: @host, rules:, kind: "private")

    assert_not outcome.refused?
    assert_equal rules, table.reload.engine_rules
    assert table.private?
    assert_empty listed
  end

  test "only the vært changes the settings, and only before the start" do
    table = create_table
    commands.sit(table:, user: @erik, seat: 1)
    rules = Hjerterfri::Rules.new(end_score: 30)

    assert_equal :not_host, commands.change_settings(table:, user: @erik, rules:, kind: "open").refusal
    2.upto(3) { |seat| commands.add_bot(table:, user: @host, seat:) }
    commands.start(table:, user: @host)
    assert_equal :not_waiting, commands.change_settings(table:, user: @host, rules:, kind: "open").refusal
    assert_equal Hjerterfri::Rules.standard, table.reload.engine_rules
  end

  # --- Handover and auto-close ---

  test "when the vært stands up, the next human in seat order takes over" do
    table = create_table
    commands.add_bot(table:, user: @host, seat: 1)
    commands.sit(table:, user: @frida, seat: 2)
    commands.sit(table:, user: @erik, seat: 3)

    commands.leave(table:, user: @host)

    assert_equal @frida, table.reload.host, "seat 1 is a bot, so seat 2 is next"
    assert_equal @frida.username, listed.sole["host"]
  end

  test "a table with only bots left closes and disappears from the lobby" do
    table = create_table
    commands.add_bot(table:, user: @host, seat: 1)

    commands.leave(table:, user: @host)

    assert table.reload.closed?
    assert_empty listed
  end

  # --- Spil igen ---

  test "Spil igen starts a new spil once every human at the table has asked for it" do
    table = finished_table
    first = table.current_game

    waiting = commands.play_again(table:, user: @erik)

    assert_equal first, table.current_game, "the vært has not asked yet"
    assert_equal [ @host.id, @erik.id ], waiting.messages.map(&:user_id)
    assert_equal [ 2 ], waiting.messages.first.payload["state"]["play_again_seats"]

    started = commands.play_again(table:, user: @host)

    second = table.current_game
    assert_not_equal first, second
    assert second.in_progress?
    assert_equal first.seats, second.seats, "the same players in the same seats"
    assert_equal [ @host.id, @erik.id ], started.messages.map(&:user_id)
    assert_equal second.id, started.messages.first.payload["state"]["game_id"]
    assert_empty started.messages.first.payload["state"]["play_again_seats"]
  end

  test "Spil igen at a practice table starts at once" do
    table = started_practice(@host, commands:)
    table.current_game.update!(status: :finished)

    commands.play_again(table:, user: @host)

    assert_equal 2, table.games.count
  end

  test "leaving after a finished spil frees the seat and sends the others back to the waiting room" do
    table = finished_table

    outcome = commands.leave(table:, user: @host)

    assert table.reload.waiting?
    assert_not table.seated?(@host)
    assert_equal @erik, table.host
    assert_equal [ [ @host.id, { "type" => "closed" } ], [ @erik.id, { "type" => "waiting" } ] ],
      outcome.messages.map { |message| [ message.user_id, message.payload ] }
    assert table.current_game.finished?, "a finished spil is not forfeited"
    assert_nil table.current_game.forfeited_by

    assert_not commands.change_settings(table:, user: @erik, rules: Hjerterfri::Rules.new(end_score: 40), kind: "open").refused?,
      "the rules may change between spil"
    assert_equal 40, table.reload.engine_rules.end_score
  end

  test "the last human leaving after a finished spil closes the table" do
    table = finished_table
    commands.leave(table:, user: @host)

    outcome = commands.leave(table:, user: @erik)

    assert table.reload.closed?
    assert_empty outcome.messages
  end

  private

  def commands(seed: 0) = TableCommands.new(scheduler: @scheduler, shuffler: Random.new(seed), random: Random.new(seed))

  def create_table = commands.create_table(user: @host).table

  def listed = LobbyChannel.tables_message["tables"]

  # A table where the vært (seat 0) and Erik (seat 2) have finished a spil
  # with two bots.
  def finished_table
    create_table.tap do |table|
      commands.sit(table:, user: @erik, seat: 2)
      commands.add_bot(table:, user: @host, seat: 1)
      commands.add_bot(table:, user: @host, seat: 3)
      commands.start(table:, user: @host)
      table.current_game.update!(status: :finished)
    end
  end
end
