require "test_helper"

# Ticket 22: each bot's level (Let, Mellem or Svær) is chosen at the bord.
# The vært picks it when adding a bot and may change it until the start; at
# a practice bord the human picks for its three bots. It is locked during a
# spil and may change between spil. A takeover bot plays Let. Driven through
# the bord's actions (WaitingTable before the start, Table once stored) and
# asserted on their outcomes, the stored seats, the spil's start snapshot
# and what each seat is sent.
class BotLevelsTest < ActiveSupport::TestCase
  setup do
    @host = users(:approved)
    @erik = users(:erik)
    @scheduler = FakeScheduler.new
  end

  # --- Before the start ---

  test "a bot plays Mellem unless the vært picks another level when adding it" do
    table = create_table

    table.add_bot(user: @host, seat: 1, surroundings:)
    table.add_bot(user: @host, seat: 2, level: "svaer", surroundings:)
    table.add_bot(user: @host, seat: 3, level: :let, surroundings:)

    assert_equal [ nil, :mellem, :svaer, :let ], table.reload.occupants.map(&:bot_level)
    assert_equal [ nil, "mellem", "svaer", "let" ], table.reload.lobby_entry["seats"].map { |seat| seat["bot_level"] }
  end

  test "the vært changes a bot's level until the start, and the spil starts with it" do
    table = create_table
    table.sit(user: @erik, seat: 2, surroundings:)
    table.add_bot(user: @host, seat: 1, surroundings:)
    table.add_bot(user: @host, seat: 3, surroundings:)

    outcome = table.change_bot_level(user: @host, seat: 3, level: "svaer", surroundings:)

    assert_not outcome.refused?
    assert_equal "svaer", outcome.table.lobby_entry["seats"][3]["bot_level"]
    stored = table.start(user: @host, surroundings:).table
    assert_equal [ nil, "mellem", nil, "svaer" ], stored.seats.order(:position).pluck(:bot_level)
    assert_equal({ "kind" => "bot", "name" => "Bot 2", "level" => "svaer" }, stored.current_game.seats[3])
  end

  test "only the vært changes a bot's level, only of a bot, and only to Let, Mellem or Svær" do
    table = create_table
    table.sit(user: @erik, seat: 2, surroundings:)
    table.add_bot(user: @host, seat: 1, surroundings:)

    assert_equal :not_host, table.change_bot_level(user: @erik, seat: 1, level: "let", surroundings:).refusal
    assert_equal :no_bot_there, table.change_bot_level(user: @host, seat: 2, level: "let", surroundings:).refusal
    assert_equal :no_bot_there, table.change_bot_level(user: @host, seat: 3, level: "let", surroundings:).refusal
    assert_equal :no_bot_there, table.change_bot_level(user: @host, seat: 9, level: "let", surroundings:).refusal
    assert_equal :unknown_bot_level, table.change_bot_level(user: @host, seat: 1, level: "umulig", surroundings:).refusal
    assert_equal :unknown_bot_level, table.add_bot(user: @host, seat: 3, level: "umulig", surroundings:).refusal
    assert_equal [ nil, :mellem, nil, nil ], table.reload.occupants.map(&:bot_level)
  end

  test "at a practice bord the human picks the level of each of the three bots before starting" do
    table = WaitingTable.set_up_practice(user: @host, surroundings:).table
    assert_equal [ nil, :mellem, :mellem, :mellem ], table.occupants.map(&:bot_level), "Mellem by default"

    %w[ let mellem svaer ].each.with_index(1) do |level, seat|
      assert_not table.change_bot_level(user: @host, seat:, level:, surroundings:).refused?
    end

    stored = table.start(user: @host, surroundings:).table
    assert_equal [ nil, "let", "mellem", "svaer" ], stored.seats.order(:position).pluck(:bot_level)
  end

  # --- During and between spil ---

  test "the levels are locked during a spil" do
    table = started_practice(@host, surroundings:)

    assert_equal :not_waiting, table.change_bot_level(user: @host, seat: 1, level: "svaer", surroundings:).refusal
    assert_equal :not_waiting, table.add_bot(user: @host, seat: 1, surroundings:).refusal
    assert_equal "mellem", table.seats.find_by!(position: 1).bot_level
  end

  test "between spil the vært changes a bot's level at the new bord, and the next spil plays with it" do
    waiting = WaitingTable.set_up_practice(user: @host, rules: Hjerterfri::Rules.new(end_score: 1), surroundings:).table
    waiting.change_bot_level(user: @host, seat: 2, level: "svaer", surroundings:)
    play_out(waiting.start(user: @host, surroundings:).table, { 0 => @host })

    next_bord = @host.current_table
    assert_kind_of WaitingTable, next_bord
    assert_equal [ nil, :mellem, :svaer, :mellem ], next_bord.occupants.map(&:bot_level), "each bot keeps its level"
    assert_not next_bord.change_bot_level(user: @host, seat: 2, level: "let", surroundings:).refused?

    stored = next_bord.start(user: @host, surroundings:).table
    assert_equal({ "kind" => "bot", "name" => "Bot 2", "level" => "let" }, stored.current_game.seats[2])
  end

  test "a bot chooses its moves at the level picked for its seat" do
    waiting = WaitingTable.set_up_practice(user: @host, surroundings:).table
    waiting.change_bot_level(user: @host, seat: 1, level: "svaer", surroundings:)
    table = waiting.start(user: @host, surroundings:).table
    turn = @scheduler.turns.find { |scheduled| scheduled[:seat] == 1 }

    bot = table.seating.occupants.fetch(1).bot_player
    assert_equal Table::BotPlayer.new(seat: 1, level: :svaer), bot
    view = table.current_game.engine_round.view_for(1)
    expected = Hjerterfri::Bot.new(level: :svaer, random: Random.new(7)).choose_pass(view)

    Table::BotPlayer.wake(**turn, surroundings: surroundings.with(random: Random.new(7)))

    assert_equal expected.sort, table.current_game.current_round.reload.passes.split[3, 3].sort
  end

  # --- Takeover ---

  test "a takeover bot plays Let, keeps Let at the next waiting bord, and the vært may change it there" do
    frida = users(:frida)
    waiting = WaitingTable.set_up(user: @host, rules: Hjerterfri::Rules.new(end_score: 1), surroundings:).table
    waiting.sit(user: @erik, seat: 2, surroundings:)
    waiting.sit(user: frida, seat: 3, surroundings:)
    waiting.add_bot(user: @host, seat: 1, level: "svaer", surroundings:)
    table = waiting.start(user: @host, surroundings:).table

    table.leave(user: @erik, surroundings:)
    assert_equal [ nil, "svaer", "let", nil ], table.seats.order(:position).pluck(:bot_level), "the takeover bot plays Let"
    play_out(table, { 0 => @host, 3 => frida })

    next_bord = @host.current_table
    assert_kind_of WaitingTable, next_bord
    assert_equal [ nil, :svaer, :let, nil ], next_bord.occupants.map(&:bot_level), "each bot keeps its level, the takeover bot Let"
    assert_not next_bord.change_bot_level(user: @host, seat: 2, level: "mellem", surroundings:).refused?
    assert_equal :mellem, next_bord.reload.occupants[2].bot_level
  end

  private

  def surroundings = Table::Surroundings.new(scheduler: @scheduler, shuffler: Random.new(0), random: Random.new(0))

  def create_table = WaitingTable.set_up(user: @host, surroundings:).table

  # Plays the spil out through the bord's actions: the humans (by seat)
  # pass their three last cards and play their first legal card, the bots
  # take their turns.
  def play_out(table, humans)
    humans.each { |seat, player| table.pass(player:, cards: table.current_game.engine_round.view_for(seat)[:hand].last(3), surroundings:) }
    500.times do
      while (turn = @scheduler.turns.shift)
        Table::BotPlayer.wake(**turn, surroundings:)
      end
      game = Game.find(table.current_game.id)
      return unless game.in_progress?

      seat = game.engine_round.to_act
      table.play(player: humans.fetch(seat), card: game.engine_round.legal_moves(seat).first, surroundings:) if humans.key?(seat)
    end
  end
end
