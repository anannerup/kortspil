require "test_helper"

# Seam 2 for host controls (ticket 13): kicking, adding and removing bots,
# changing the rules and the table type before the start (at the bord
# waiting in memory), vært handover, auto-close, and "Spil igen" with the
# same players. Driven through
# the bord's actions and asserted on their outcomes, the stored rows and what the
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
    table.sit(user: @erik, seat: 2, surroundings:)

    outcome = table.kick(user: @host, seat: 2, surroundings:)

    assert_not outcome.refused?
    assert_not table.reload.seated?(@erik)
    assert table.reload.seating.occupants.fetch(2).empty?
    assert_nil @erik.current_table
    assert_not table.sit(user: @erik, seat: 2, surroundings:).refused?, "a kick is not a ban"
  end

  test "only the vært may kick, only a human other than themself, and only before the start" do
    table = create_table
    table.sit(user: @erik, seat: 1, surroundings:)
    table.add_bot(user: @host, seat: 2, surroundings:)

    assert_equal :not_host, table.kick(user: @erik, seat: 0, surroundings:).refusal
    assert_equal :nobody_to_kick, table.kick(user: @host, seat: 0, surroundings:).refusal, "the vært stands up instead"
    assert_equal :nobody_to_kick, table.kick(user: @host, seat: 2, surroundings:).refusal, "a bot is removed, not kicked"
    assert_equal :nobody_to_kick, table.kick(user: @host, seat: 3, surroundings:).refusal
    assert_equal :no_such_seat, table.kick(user: @host, seat: 7, surroundings:).refusal
    assert table.reload.seated?(@erik)

    table.add_bot(user: @host, seat: 3, surroundings:)
    table = table.start(user: @host, surroundings:).table
    assert_equal :not_waiting, table.kick(user: @host, seat: 1, surroundings:).refusal
    assert table.reload.seated?(@erik)
  end

  # --- Bots ---

  test "the vært puts bots in empty seats and removes them again; the lobby shows them" do
    table = create_table

    assert_not table.add_bot(user: @host, seat: 1, surroundings:).refused?
    assert_not table.add_bot(user: @host, seat: 3, surroundings:).refused?

    assert_equal [ @host.username, "Bot 1", nil, "Bot 2" ], table.reload.seating.occupants.map(&:name)
    assert_equal [ false, true, false, true ], listed.sole["seats"].map { |seat| seat["bot"] }
    assert_equal [ nil, "mellem", nil, "mellem" ], listed.sole["seats"].map { |seat| seat["bot_level"] }, "a bot plays Mellem until the vært can choose"

    assert_not table.remove_bot(user: @host, seat: 1, surroundings:).refused?
    assert table.reload.seating.occupants.fetch(1).empty?
    assert_equal :no_bot_there, table.remove_bot(user: @host, seat: 1, surroundings:).refusal
    assert_equal :no_bot_there, table.remove_bot(user: @host, seat: 0, surroundings:).refusal
  end

  test "only the vært adds or removes bots, only in a free seat, and only before the start" do
    table = create_table
    table.sit(user: @erik, seat: 1, surroundings:)

    assert_equal :not_host, table.add_bot(user: @erik, seat: 2, surroundings:).refusal
    assert_equal :seat_taken, table.add_bot(user: @host, seat: 1, surroundings:).refusal
    assert_equal :no_such_seat, table.add_bot(user: @host, seat: 4, surroundings:).refusal
    table.add_bot(user: @host, seat: 2, surroundings:)
    assert_equal :not_host, table.remove_bot(user: @erik, seat: 2, surroundings:).refusal

    table.add_bot(user: @host, seat: 3, surroundings:)
    table = table.start(user: @host, surroundings:).table
    assert_equal :not_waiting, table.remove_bot(user: @host, seat: 2, surroundings:).refusal
    assert table.reload.seating.occupants.fetch(2).bot?
  end

  test "a spil starts with bots in the empty seats, and the bots are scheduled to pass" do
    table = create_table
    table.sit(user: @erik, seat: 2, surroundings:)
    table.add_bot(user: @host, seat: 1, surroundings:)
    table.add_bot(user: @host, seat: 3, surroundings:)

    outcome = table.start(user: @host, surroundings:)

    assert_not outcome.refused?
    assert_equal [ { "kind" => "human", "user_id" => @host.id }, { "kind" => "bot", "name" => "Bot 1" },
                   { "kind" => "human", "user_id" => @erik.id }, { "kind" => "bot", "name" => "Bot 2" } ], outcome.table.current_game.seats
    assert_equal [ 1, 3 ], @scheduler.turns.map { |turn| turn[:seat] }
    assert_equal [ nil, "mellem", nil, "mellem" ], outcome.table.seats.order(:position).pluck(:bot_level), "each bot's level is stored in its seat"
    assert_equal [ @host.id, @erik.id ], outcome.messages.map(&:user_id)
  end

  # --- Settings ---

  test "the vært changes the rules and the table type before the start" do
    table = create_table
    rules = Hjerterfri::Rules.new(end_score: 30, queen_breaks_hearts: true)

    outcome = table.change_settings(user: @host, rules:, kind: "private", surroundings:)

    assert_not outcome.refused?
    assert_equal rules, table.reload.rules.game
    assert table.reload.private?
    assert_empty listed
  end

  test "only the vært changes the settings, and only before the start" do
    table = create_table
    table.sit(user: @erik, seat: 1, surroundings:)
    rules = Hjerterfri::Rules.new(end_score: 30)

    assert_equal :not_host, table.change_settings(user: @erik, rules:, kind: "open", surroundings:).refusal
    2.upto(3) { |seat| table.add_bot(user: @host, seat:, surroundings:) }
    table = table.start(user: @host, surroundings:).table
    assert_equal :not_waiting, table.change_settings(user: @host, rules:, kind: "open", surroundings:).refusal
    assert_equal Hjerterfri::Rules.standard, table.reload.rules.game
  end

  # --- Handover and auto-close ---

  test "when the vært stands up, the next human in seat order takes over" do
    table = create_table
    table.add_bot(user: @host, seat: 1, surroundings:)
    table.sit(user: @frida, seat: 2, surroundings:)
    table.sit(user: @erik, seat: 3, surroundings:)

    table.leave(user: @host, surroundings:)

    assert_equal @frida, table.reload.host, "seat 1 is a bot, so seat 2 is next"
    assert_equal @frida.username, listed.sole["host"]
  end

  test "a table with only bots left closes and disappears from the lobby" do
    table = create_table
    table.add_bot(user: @host, seat: 1, surroundings:)

    table.leave(user: @host, surroundings:)

    assert table.reload.closed?
    assert_empty listed
  end

  # --- Spil igen ---

  test "Spil igen starts a new spil once every human at the table has asked for it" do
    table = finished_table
    first = table.current_game

    waiting = table.play_again(user: @erik, surroundings:)

    assert_equal first, table.current_game, "the vært has not asked yet"
    assert_equal [ @host.id, @erik.id ], waiting.messages.map(&:user_id)
    assert_equal [ 2 ], waiting.messages.first.payload["state"]["play_again_seats"]

    started = table.play_again(user: @host, surroundings:)

    second = table.current_game
    assert_not_equal first, second
    assert second.in_progress?
    assert_equal first.seats, second.seats, "the same players in the same seats"
    assert_equal [ @host.id, @erik.id ], started.messages.map(&:user_id)
    assert_equal second.id, started.messages.first.payload["state"]["game_id"]
    assert_empty started.messages.first.payload["state"]["play_again_seats"]
  end

  test "Spil igen at a practice table starts at once" do
    table = started_practice(@host, surroundings:)
    table.current_game.update!(status: :finished)

    table.play_again(user: @host, surroundings:)

    assert_equal 2, table.games.count
  end

  test "leaving after a finished spil closes the stored bord; the others wait at a new bord in the lobby" do
    table = finished_table

    outcome = table.leave(user: @host, surroundings:)

    assert table.reload.closed?
    waiting = @erik.current_table
    assert_kind_of WaitingTable, waiting
    assert_nil @host.current_table
    assert_equal @erik.id, waiting.host_id, "the vært left, so the next human in seat order"
    assert_equal [ nil, "Bot 1", @erik.username, "Bot 2" ], waiting.occupants.map(&:name)
    assert_equal [ [ @host.id, { "type" => "closed" } ], [ @erik.id, { "type" => "waiting", "path" => "/borde/#{waiting.id}" } ] ],
      outcome.messages.map { |message| [ message.user_id, message.payload ] }
    assert table.current_game.finished?, "a finished spil is not forfeited"
    assert_nil table.current_game.forfeited_by
    assert_equal waiting.id, listed.first["id"]

    assert_not waiting.change_settings(user: @erik, rules: Hjerterfri::Rules.new(end_score: 40), kind: "open", surroundings:).refused?,
      "the rules may change between spil"
    assert_equal 40, waiting.reload.rules.game.end_score
    assert_no_difference -> { Table.count } do
      waiting.sit(user: @host, seat: 0, surroundings:)
    end
    assert_difference -> { Table.count } do
      assert_not waiting.start(user: @erik, surroundings:).refused?
    end
  end

  test "the last human leaving after a finished spil closes the table, and the bord waiting for the next spil" do
    table = finished_table
    table.leave(user: @host, surroundings:)
    waiting = @erik.current_table

    waiting.leave(user: @erik, surroundings:)

    assert table.reload.closed?
    assert waiting.reload.closed?
    assert_nil @erik.current_table
  end

  private

  def surroundings(seed: 0) = Table::Surroundings.new(scheduler: @scheduler, shuffler: Random.new(seed), random: Random.new(seed))

  def create_table = WaitingTable.set_up(user: @host, surroundings:).table

  def listed = LobbyChannel.tables_message["tables"]

  # A table where the vært (seat 0) and Erik (seat 2) have finished a spil
  # with two bots.
  def finished_table
    waiting = create_table
    waiting.sit(user: @erik, seat: 2, surroundings:)
    waiting.add_bot(user: @host, seat: 1, surroundings:)
    waiting.add_bot(user: @host, seat: 3, surroundings:)
    waiting.start(user: @host, surroundings:).table.tap { |table| table.current_game.update!(status: :finished) }
  end
end
