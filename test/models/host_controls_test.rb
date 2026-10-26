require "test_helper"

# Seam 2 for host controls (ticket 13): kicking, adding and removing bots,
# changing the rules and the table type before the start (at the bord
# waiting in memory), vært handover, auto-close, and the new bord everyone
# moves to when the spil ends. Driven through
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
    assert_equal [ nil, "mellem", nil, "mellem" ], listed.sole["seats"].map { |seat| seat["bot_level"] }, "a bot plays Mellem unless the vært picks another level"

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
    assert_equal [ { "kind" => "human", "user_id" => @host.id }, { "kind" => "bot", "name" => "Bot 1", "level" => "mellem" },
                   { "kind" => "human", "user_id" => @erik.id }, { "kind" => "bot", "name" => "Bot 2", "level" => "mellem" } ], outcome.table.current_game.seats
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

  # --- After the spil ---

  test "when the spil ends, everyone at the bord waits at a new bord in the lobby: same seats, vært, rules and chat; bots keep their levels" do
    table = started_table(rules: Hjerterfri::Rules.new(end_score: 1))
    Seat.find_by!(table:, position: 3).update!(bot_level: "let")
    table.chat(user: @erik, text: "Godt spil", surroundings:)

    outcome = play_out(table)

    assert table.current_game.finished?
    assert table.reload.closed?
    waiting = @erik.current_table
    assert_kind_of WaitingTable, waiting
    assert_equal waiting, @host.current_table
    assert_equal [ @host.username, "Bot 1", @erik.username, "Bot 2" ], waiting.occupants.map(&:name)
    assert_equal [ nil, :mellem, nil, :let ], waiting.occupants.map { |occupant| occupant.bot_level&.to_sym }
    assert_equal [ @host.id, "open", 1, "hjerterfri" ], [ waiting.host_id, waiting.kind, waiting.rules.game.end_score, waiting.game ]
    assert_equal [ "Godt spil" ], waiting.chat_history(user: @erik, surroundings:).messages.sole.payload["messages"].map { |message| message["text"] }
    assert_equal waiting.id, listed.first["id"]
    assert_equal [ @host.id, @erik.id ], outcome.messages.map(&:user_id)
    assert_equal [ "/borde/#{waiting.id}" ] * 2, outcome.messages.map { |message| message.payload["state"]["next_path"] },
      "each human sees the final result, with the way to the new bord"
    assert_equal "finished", outcome.messages.first.payload["state"]["status"]
  end

  test "at the new bord each player stays to play again or stands up; the vært starts when every seat is filled" do
    table = started_table(rules: Hjerterfri::Rules.new(end_score: 1))
    play_out(table)
    waiting = @erik.current_table

    waiting.leave(user: @erik, surroundings:)

    assert_nil @erik.current_table
    assert_nil table.current_game.reload.forfeited_by, "standing up after a finished spil is no loss"
    assert_equal :seats_not_filled, waiting.start(user: @host, surroundings:).refusal
    assert_not waiting.change_settings(user: @host, rules: Hjerterfri::Rules.new(end_score: 40), kind: "open", surroundings:).refused?,
      "the rules may change between spil"
    waiting.sit(user: @frida, seat: 2, surroundings:)
    started = nil
    assert_difference -> { Table.count } do
      started = waiting.start(user: @host, surroundings:)
    end
    assert_not started.refused?
    assert_equal 40, started.table.rules.game.end_score
    assert_equal [ @host.username, "Bot 1", @frida.username, "Bot 2" ], started.table.seating.occupants.map(&:name)
  end

  test "the last human standing up from the new bord closes it" do
    table = started_table(rules: Hjerterfri::Rules.new(end_score: 1))
    play_out(table)
    waiting = @erik.current_table

    waiting.leave(user: @erik, surroundings:)
    waiting.leave(user: @host, surroundings:)

    assert waiting.reload.closed?
    assert_nil @host.current_table
    assert_empty table.reload.leave(user: @host, surroundings:).messages, "the stored bord is closed"
  end

  private

  def surroundings(seed: 0) = Table::Surroundings.new(scheduler: @scheduler, shuffler: Random.new(seed), random: Random.new(seed))

  def create_table = WaitingTable.set_up(user: @host, surroundings:).table

  def listed = LobbyChannel.tables_message["tables"]

  # A stored table where the vært (seat 0) and Erik (seat 2) play a spil
  # with two bots.
  def started_table(rules: Hjerterfri::Rules.standard)
    waiting = WaitingTable.set_up(user: @host, rules:, surroundings:).table
    waiting.sit(user: @erik, seat: 2, surroundings:)
    waiting.add_bot(user: @host, seat: 1, surroundings:)
    waiting.add_bot(user: @host, seat: 3, surroundings:)
    waiting.start(user: @host, surroundings:).table
  end

  # Plays the spil out through the bord's actions: the humans pass their
  # three last cards and play their first legal card, the bots take their
  # turns. Returns the outcome of the move that ended the spil.
  def play_out(table)
    humans = { 0 => @host, 2 => @erik }
    last = nil
    humans.each { |seat, player| last = player_acts(table, :pass, player:, cards: table.current_game.engine_round.view_for(seat)[:hand].last(3), surroundings:) }
    500.times do
      while (turn = @scheduler.turns.shift)
        last = Table::BotPlayer.wake(**turn, surroundings:)
      end
      game = Game.find(table.current_game.id)
      return last unless game.in_progress?

      seat = game.engine_round.to_act
      last = player_acts(table, :play, player: humans.fetch(seat), card: game.engine_round.legal_moves(seat).first, surroundings:) if humans.key?(seat)
      raise "stuck" unless humans.key?(seat) || @scheduler.turns.any?
    end
  end
end
