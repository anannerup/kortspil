require "test_helper"

# Seam 2 for open tables (ticket 12): creating a table in the lobby,
# sitting and standing before the start (in memory: nothing is stored until
# the spil starts), one bord per user, the start condition, and several
# humans playing a spil together. Driven through
# TableCommands and asserted on its outcomes, the stored rows and what the
# lobby is sent. Leaving a spil in progress and absence are in
# TableAbsenceTest (tickets 18 and 19).
class OpenTablesTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  setup do
    @host = users(:approved)
    @players = [ @host, users(:admin), users(:erik), users(:frida) ]
    @scheduler = FakeScheduler.new
  end

  # --- Creating and listing ---

  test "creating a table seats the vært in seat 0 with the chosen rules, and the lobby lists it" do
    rules = Hjerterfri::Rules.new(end_score: 50, shooters_choice: true)

    outcome = commands.create_table(user: @host, rules:)

    table = outcome.table
    assert_not outcome.refused?
    assert_kind_of WaitingTable, table
    assert table.open?
    assert table.waiting?
    assert_equal "hjerterfri", table.game
    assert_equal @host, table.host
    assert_equal rules, table.engine_rules
    assert_equal 0, table.reload.seating.seat_of(@host)
    assert_equal table, @host.current_table
    entry = listed.sole
    assert_equal [ table.id, @host.username, "waiting", rules.to_h.as_json, "/borde/#{table.id}" ], entry.values_at("id", "host", "status", "rules", "path")
    assert_equal [ @host.username, nil, nil, nil ], entry["seats"].map { |seat| seat["name"] }
  end

  test "nothing is stored before the start: no table, seats or spil" do
    assert_no_difference %w[ Table.count Seat.count Game.count ] do
      table = create_table
      commands.sit(table:, user: users(:erik), seat: 1)
      commands.add_bot(table:, user: @host, seat: 2)
      commands.change_settings(table:, user: @host, rules: Hjerterfri::Rules.new(end_score: 50), kind: "private")
      commands.start_practice(user: users(:frida))
    end
  end

  test "only a bord for a game that is built can be made" do
    assert_equal :game_not_available, commands.create_table(user: @host, game: "es_makker").refusal
    assert_nil @host.current_table
  end

  test "starting stores the bord, its seats and the spil together, and the old link leads to it" do
    waiting = full_table
    chat = TableChat.default
    chat.post(waiting.id, author: waiting.reload.occupants.first, text: "Hej")

    table = nil
    assert_difference({ "Table.count" => 1, "Seat.count" => 4, "Game.count" => 1 }) do
      table = commands.start(table: waiting, user: @host).table
    end

    assert table.playing?
    assert_equal [ @host, waiting.rules, "open" ], [ table.host, table.rules, table.kind ]
    assert_equal @players.map(&:username), table.seating.occupants.map(&:name)
    assert_nil WaitingTables.default.find(waiting.id)
    assert waiting.reload.closed?
    assert_equal table.id, WaitingTables.default.started_as(waiting.id)
    assert_equal table, @host.current_table
    assert_equal [ "Hej" ], chat.messages(table.id).map(&:text), "the chat comes along"
    assert_equal [ table.id ], listed.map { |entry| entry["id"] }
  end

  test "practice tables and closed tables are not listed" do
    commands.start_practice(user: users(:erik))
    table = create_table
    assert_equal [ table.id ], listed.map { |entry| entry["id"] }

    commands.leave(table:, user: @host)

    assert table.reload.closed?
    assert_empty listed
  end

  test "the lobby is sent the list whenever a listed table or its seats change" do
    table = nil
    assert_broadcasts(LobbyChannel::STREAM, 1) { table = create_table }

    assert_broadcasts(LobbyChannel::STREAM, 1) { commands.sit(table:, user: users(:erik), seat: 2) }
    assert_equal [ @host.username, nil, "Erik", nil ], broadcasts(LobbyChannel::STREAM).last.then { |json| JSON.parse(json) }["tables"].sole["seats"].map { |seat| seat["name"] }
    assert_no_broadcasts(LobbyChannel::STREAM) { commands.start_practice(user: users(:frida)) }
  end

  # --- Sitting and standing before the start ---

  test "players choose a free seat and may move to another free seat" do
    table = create_table

    assert_not commands.sit(table:, user: users(:erik), seat: 2).refused?
    assert_not commands.sit(table:, user: users(:erik), seat: 3).refused?

    assert_equal [ @host.username, nil, nil, "Erik" ], table.reload.seating.occupants.map(&:name)
  end

  test "a taken seat or one that does not exist is refused and nothing changes" do
    table = create_table
    commands.sit(table:, user: users(:erik), seat: 2)

    assert_equal :seat_taken, commands.sit(table:, user: users(:frida), seat: 2).refusal
    assert_equal :seat_taken, commands.sit(table:, user: users(:erik), seat: 0).refusal
    assert_equal :no_such_seat, commands.sit(table:, user: users(:frida), seat: 4).refusal
    assert_equal :no_such_seat, commands.sit(table:, user: users(:frida), seat: nil).refusal
    assert_equal [ @host.username, nil, "Erik", nil ], table.reload.seating.occupants.map(&:name)
  end

  test "standing up before the start frees the seat without touching any spil" do
    table = create_table
    commands.sit(table:, user: users(:erik), seat: 1)

    outcome = commands.leave(table:, user: users(:erik))

    assert_empty outcome.messages
    assert_not table.reload.seated?(users(:erik))
    assert table.reload.waiting?
    assert_nil users(:erik).current_table
  end

  test "when the vært stands up the next human in seat order becomes vært; the last human closes the table" do
    table = create_table
    commands.sit(table:, user: users(:frida), seat: 1)
    commands.sit(table:, user: users(:erik), seat: 3)
    commands.sit(table:, user: @host, seat: 2)

    commands.leave(table:, user: @host)
    assert_equal users(:erik), table.reload.host, "after seat 2 comes seat 3"

    commands.leave(table:, user: users(:erik))
    assert_equal users(:frida), table.reload.host
    assert table.waiting?

    commands.leave(table:, user: users(:frida))
    assert table.reload.closed?
  end

  # --- One bord per user ---

  test "a player sitting at one bord is refused a seat at a second one" do
    first = create_table
    second = commands.create_table(user: users(:erik)).table

    outcome = commands.sit(table: second, user: @host, seat: 1)

    assert_equal :seated_elsewhere, outcome.refusal
    assert_not second.seated?(@host)
    assert_equal first, @host.current_table
  end

  test "a player sitting at a bord cannot create another or start a practice table" do
    create_table

    assert_no_difference -> { Table.count } do
      assert_equal :seated_elsewhere, commands.create_table(user: @host).refusal
      assert_equal :seated_elsewhere, commands.start_practice(user: @host).refusal
    end
  end

  test "a practice table counts as a bord too, until the player leaves it" do
    practice = commands.start_practice(user: users(:erik)).table
    table = create_table

    assert_equal :seated_elsewhere, commands.sit(table:, user: users(:erik), seat: 1).refusal

    commands.leave(table: practice, user: users(:erik))
    assert_not commands.sit(table:, user: users(:erik), seat: 1).refused?
  end

  test "after standing up the player may sit at another bord" do
    first = create_table
    second = commands.create_table(user: users(:erik)).table
    commands.sit(table: first, user: users(:frida), seat: 1)

    commands.leave(table: first, user: users(:frida))

    assert_not commands.sit(table: second, user: users(:frida), seat: 1).refused?
  end

  # --- Starting ---

  test "only the vært can start, and only once all four seats are taken" do
    table = create_table
    commands.sit(table:, user: users(:erik), seat: 1)
    commands.sit(table:, user: users(:frida), seat: 2)

    assert_equal :seats_not_filled, commands.start(table:, user: @host).refusal
    commands.sit(table:, user: users(:admin), seat: 3)
    assert_equal :not_host, commands.start(table:, user: users(:erik)).refusal
    assert table.reload.waiting?
    assert_equal 0, Table.count

    stored = commands.start(table:, user: @host)
    assert_not stored.refused?
    assert stored.table.playing?
    assert_equal :not_waiting, commands.start(table:, user: @host).refusal
    assert_equal :not_waiting, commands.start(table: stored.table, user: @host).refusal
    assert_equal 1, stored.table.games.count
  end

  test "once started, nobody can sit, move or change the rules, and the lobby shows it in progress" do
    table = full_table
    table = commands.start(table:, user: @host).table

    assert_equal :not_waiting, commands.sit(table:, user: users(:erik), seat: 1).refusal
    assert_not table.reload.update(rules: Hjerterfri::Rules.new(end_score: 10).to_h)
    assert_equal "playing", listed.sole["status"]
  end

  # --- Playing together ---

  test "starting deals runde 1 and every human gets their own state with only their own hand" do
    table = full_table

    outcome = commands.start(table:, user: @host)

    table = outcome.table
    game = table.current_game
    assert_equal @players.map { |player| { "kind" => "human", "user_id" => player.id } }, game.seats
    assert_equal table.engine_rules, game.engine_rules
    assert_empty @scheduler.turns, "no bots to schedule"
    assert_equal @players.map(&:id), outcome.messages.map(&:user_id)
    outcome.messages.each do |message|
      view = message.payload["state"]["view"]
      assert_equal message.seat, view["seat"]
      assert_equal hand_of(table, message.seat).sort, view["hand"].sort
      assert_empty card_codes_in(message.payload) - hand_of(table, message.seat), "seat #{message.seat} sees only its own cards"
      assert_equal @players.map(&:username), message.payload["state"]["seats"].map { |seat| seat["name"] }
    end
  end

  test "four humans pass and play, and each move reaches every seat" do
    table = full_table
    table = commands.start(table:, user: @host).table

    @players.each_with_index do |player, seat|
      outcome = commands.pass(table:, user: player, cards: hand_of(table, seat).last(3))
      assert_equal @players.map(&:id), outcome.messages.map(&:user_id)
    end
    leader = live(table).engine_round.to_act

    outcome = commands.play(table:, user: @players[leader], card: "2C")

    assert_equal "2C", table.current_game.current_round.reload.plays
    outcome.messages.each do |message|
      assert_equal [ { "seat" => leader, "card" => "2C" } ], message.payload["state"]["view"]["current_trick"]
    end
    other = @players[(leader + 1) % 4]
    assert_rejected "not_your_turn", commands.play(table:, user: @players[(leader + 2) % 4], card: hand_of(table, (leader + 2) % 4).first)
    assert_equal (leader + 1) % 4, connect_state(table, other)["view"]["to_act"]
  end

  private

  def commands(seed: 0) = TableCommands.new(scheduler: @scheduler, shuffler: Random.new(seed), random: Random.new(seed))

  def create_table = commands.create_table(user: @host).table

  # A table with the four players in seats 0–3, not yet started.
  def full_table
    create_table.tap do |table|
      @players.drop(1).each.with_index(1) { |player, seat| commands.sit(table:, user: player, seat:) }
    end
  end

  def listed = LobbyChannel.tables_message["tables"]

  def live(table) = LiveGame.load(table.current_game.reload)

  def connect_state(table, user) = commands.connect(table: Table.find(table.id), user:).messages.sole.payload["state"]

  def hand_of(table, seat) = table.current_game.current_round.reload.then { |round| round.to_engine(table.engine_rules).view_for(seat)[:hand] }

  def assert_rejected(reason, outcome)
    assert_equal [ "rejected", reason ], outcome.messages.sole.payload.values_at("type", "reason")
  end

  def card_codes_in(payload)
    payload.to_json.scan(/"([2-9TJQKA][CDHS])"/).flatten.uniq
  end
end
