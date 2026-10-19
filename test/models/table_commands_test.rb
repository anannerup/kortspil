require "test_helper"

# Seam 2: the table command interface, driven through its commands and
# asserted on the messages it returns and the rows it stores.
class TableCommandsTest < ActiveSupport::TestCase
  # Records bot turns instead of enqueuing jobs, so tests run them by hand.
  class FakeScheduler
    attr_reader :turns

    def initialize = @turns = []
    def schedule(**turn) = @turns << turn
  end

  setup do
    @user = users(:approved)
    @scheduler = FakeScheduler.new
  end

  test "starting a practice table seats the user and three bots and deals a runde" do
    outcome = commands(seed: seed_where_human_leads).start_practice(user: @user)

    table = outcome.table
    game = table.current_game
    assert table.practice?
    assert table.playing?
    assert_equal @user, table.host
    assert_equal [ "human", "bot", "bot", "bot" ], game.seats.map { |seat| seat["kind"] }
    assert_equal 52, game.current_round.deal.split.size
    assert_equal "", game.current_round.plays

    assert_equal [ 0 ], outcome.messages.map(&:seat)
    state = outcome.messages.first.payload["state"]
    assert_equal 13, state["view"]["hand"].size
    assert_equal 0, state["view"]["to_act"]
    assert_equal [ @user.username, "Bot 1", "Bot 2", "Bot 3" ], state["seats"].map { |seat| seat["name"] }
    assert_empty @scheduler.turns
  end

  test "when a bot holds 2♣ its turn is scheduled at the start" do
    commands(seed: seed_where_bot_leads).start_practice(user: @user)

    turn = @scheduler.turns.sole
    assert_operator turn[:seat], :>, 0
    assert_equal 0, turn[:version]
    assert_includes Hjerterfri::Bot::DELAY_SECONDS, turn[:delay]
  end

  test "a legal play is stored and the human gets the new state" do
    table = start_practice(seed: seed_where_human_leads)

    outcome = commands.play(table:, user: @user, card: "2C")

    assert_equal "2C", table.current_game.current_round.reload.plays
    message = outcome.messages.sole
    assert_equal 0, message.seat
    assert_equal "state", message.payload["type"]
    assert_equal [ { "seat" => 0, "card" => "2C" } ], message.payload["state"]["view"]["current_trick"]
    assert_equal 1, message.payload["state"]["version"]
    assert_equal({ game_id: table.current_game.id, seat: 1, version: 1 }, @scheduler.turns.last.except(:delay))
  end

  test "an illegal play is rejected to that seat only and nothing is stored" do
    table = start_practice(seed: seed_where_human_leads)
    other_card = (hand_of(table, 0) - [ "2C" ]).first

    outcome = commands.play(table:, user: @user, card: other_card)

    message = outcome.messages.sole
    assert_equal 0, message.seat
    assert_equal @user.id, message.user_id
    assert_equal({ "type" => "rejected", "reason" => "must_lead_two_of_clubs", "card" => other_card }, message.payload)
    assert_equal "", table.current_game.current_round.reload.plays
    assert_empty @scheduler.turns
  end

  test "a play out of turn is rejected" do
    table = start_practice(seed: seed_where_bot_leads)

    outcome = commands.play(table:, user: @user, card: hand_of(table, 0).first)

    assert_equal "not_your_turn", outcome.messages.sole.payload["reason"]
  end

  test "a user who does not sit at the table gets no messages and changes nothing" do
    table = start_practice(seed: seed_where_human_leads)

    outcome = commands.play(table:, user: users(:admin), card: "2C")

    assert_empty outcome.messages
    assert_equal "", table.current_game.current_round.reload.plays
  end

  test "bots play their turns until it is the human's turn again" do
    table = start_practice(seed: seed_where_human_leads)
    commands.play(table:, user: @user, card: "2C")

    messages = run_bot_turns

    round = table.current_game.current_round.reload
    assert_operator round.plays_made, :>=, 4
    assert_equal round.plays_made - 1, messages.size
    state = messages.last.payload["state"]
    assert_equal round.plays_made, state["version"]
    assert_equal 0, state["view"]["to_act"]
    assert_not_empty state["view"]["legal_moves"]
    assert_empty @scheduler.turns
  end

  test "a stale bot turn does nothing" do
    table = start_practice(seed: seed_where_bot_leads)
    turn = @scheduler.turns.first
    run_bot_turns
    plays = table.current_game.current_round.reload.plays

    outcome = commands.bot_turn(**turn.except(:delay))

    assert_empty outcome.messages
    assert_empty @scheduler.turns
    assert_equal plays, table.current_game.current_round.reload.plays
  end

  test "a full runde against bots ends with points shown and the game finished" do
    table = start_practice(seed: seed_where_bot_leads)

    last_state = play_out(table)

    view = last_state["view"]
    assert_equal "complete", view["phase"]
    assert_includes [ 26, 78 ], view["points"].sum
    assert_equal 52, table.current_game.current_round.reload.plays_made
    assert table.current_game.reload.finished?
    assert table.reload.closed?
    assert_equal "round_complete", commands.play(table:, user: @user, card: "2C").messages.sole.payload["reason"]
  end

  test "messages only ever reveal the seat's own hand and cards already played" do
    table = start_practice(seed: seed_where_bot_leads)
    own_hand = hand_of(table, 0)
    messages = []

    play_out(table) { |outcome| messages.concat(outcome.messages) }

    assert messages.all? { |message| message.seat == 0 && message.user_id == @user.id }
    plays = table.current_game.current_round.reload.plays.split
    messages.each do |message|
      played_so_far = plays.first(message.payload["state"]["version"])
      assert_empty card_codes_in(message.payload) - own_hand - played_so_far
    end
  end

  test "rebuilding from the database mid-runde gives the same state" do
    table = start_practice(seed: seed_where_human_leads)
    commands.play(table:, user: @user, card: "2C")
    live = run_bot_turns.last

    rebuilt = TableCommands.new(scheduler: FakeScheduler.new).connect(table: Table.find(table.id), user: @user)

    assert_equal live.payload, rebuilt.messages.sole.payload
  end

  test "connecting while a bot is to act schedules its turn again" do
    table = start_practice(seed: seed_where_bot_leads)
    scheduler = FakeScheduler.new

    TableCommands.new(scheduler:).connect(table:, user: @user)

    assert_equal @scheduler.turns.first.except(:delay), scheduler.turns.sole.except(:delay)
  end

  private

  def commands(seed: 0) = TableCommands.new(scheduler: @scheduler, shuffler: Random.new(seed), random: Random.new(seed))

  def start_practice(seed:) = commands(seed:).start_practice(user: @user).table

  def seed_where_human_leads = seed_where { |holder| holder.zero? }
  def seed_where_bot_leads = seed_where(&:positive?)

  def seed_where
    (0..).find { |seed| yield Hjerterfri::Deal.shuffled(shuffler: Random.new(seed)).holder_of(Hjerterfri::Card::TWO_OF_CLUBS) }
  end

  def hand_of(table, seat) = table.current_game.current_round.deal.split.each_slice(13).to_a.fetch(seat)

  # Runs scheduled bot turns, oldest first, until none are left. Returns
  # the messages they produced.
  def run_bot_turns
    messages = []
    while (turn = @scheduler.turns.shift)
      outcome = commands.bot_turn(**turn.except(:delay))
      yield outcome if block_given?
      messages.concat(outcome.messages)
    end
    messages
  end

  # Plays the runde out: the human plays their first legal card, bots run in
  # between. Returns the last state the human received.
  def play_out(table, &observe)
    state = nil
    52.times do
      run_bot_turns(&observe).last&.then { |message| state = message.payload["state"] }
      break if state && state["view"]["phase"] == "complete"

      card = state ? state["view"]["legal_moves"].first : "2C"
      outcome = commands.play(table:, user: @user, card:)
      observe&.call(outcome)
      state = outcome.messages.sole.payload.fetch("state")
    end
    state
  end

  def card_codes_in(payload)
    payload.to_json.scan(/"([2-9TJQKA][CDHS])"/).flatten.uniq
  end
end
