require "test_helper"

class TableChannelTest < ActionCable::Channel::TestCase
  setup do
    @user = users(:approved)
    @table = started_practice(@user)
    @stream = TableChannel.stream_name(@table.id, @user.id)
    TableChat.default.forget(@table.id)
  end

  test "a seated user subscribes to their own stream and gets the state" do
    stub_connection current_user: @user

    subscribe table_id: @table.id

    assert subscription.confirmed?
    assert_has_stream @stream
    assert_equal "state", transmissions.last["type"]
    assert_equal "passing", transmissions.last["state"]["view"]["phase"]
  end

  test "a pass is answered on the user's stream and stored" do
    stub_connection current_user: @user
    subscribe table_id: @table.id
    cards = transmissions.last["state"]["view"]["hand"].last(3)

    assert_broadcasts(@stream, 1) { perform :pass, cards: }

    assert_equal cards.sort, @table.current_game.current_round.reload.passes.split.first(3).sort
  end

  test "a play during the pass is rejected on the user's stream" do
    stub_connection current_user: @user
    subscribe table_id: @table.id

    assert_broadcast_on(@stream, { "type" => "rejected", "reason" => "passing_not_complete", "card" => "AH" }) do
      perform :play, card: "AH"
    end
  end

  test "next runde and play again do nothing while the runde is in progress" do
    stub_connection current_user: @user
    subscribe table_id: @table.id

    assert_no_broadcasts(@stream) do
      perform :next_runde
      perform :play_again
    end
  end

  test "a heartbeat keeps the seat heard from" do
    stub_connection current_user: @user
    subscribe table_id: @table.id

    travel 5.seconds do
      perform :heartbeat
      assert_in_delta Time.current, Seat.find_by(table: @table, user: @user).heartbeat_at, 1
    end
  end

  test "closing the subscription in a spil in progress at an open table makes the seat frakoblet and tells the others" do
    players = [ users(:approved), users(:admin), users(:erik), users(:frida) ]
    commands = TableCommands.new(scheduler: FakeScheduler.new)
    commands.leave(table: @table, user: @user)
    table = commands.create_table(user: players.first).table
    players.drop(1).each.with_index(1) { |player, seat| commands.sit(table:, user: player, seat:) }
    table = commands.start(table:, user: players.first).table
    stub_connection current_user: users(:erik)
    subscribe table_id: table.id

    assert_broadcasts(TableChannel.stream_name(table.id, players.first.id), 1) { unsubscribe }

    assert table.seating.occupants[2].frakoblet?
  end

  test "a user who does not sit at the table is rejected" do
    stub_connection current_user: users(:admin)

    subscribe table_id: @table.id

    assert subscription.rejected?
  end

  test "a closed table rejects the subscription" do
    TableCommands.new.leave(table: @table, user: @user)
    stub_connection current_user: @user

    subscribe table_id: @table.id

    assert subscription.rejected?
  end

  test "chat is posted on the stream and replayed on subscribing again" do
    stub_connection current_user: @user
    subscribe table_id: @table.id
    assert_equal({ "type" => "chat_history", "messages" => [], "max_length" => TableChat::MAX_LENGTH }, transmissions.first)

    assert_broadcasts(@stream, 1) { perform :chat, text: "Hej bots" }

    unsubscribe
    subscribe table_id: @table.id
    assert_equal [ "Hej bots" ], transmissions.find { |message| message["type"] == "chat_history" && message["messages"].any? }["messages"].map { |message| message["text"] }
  end

  test "at a table that has not started a seated user gets only the chat" do
    table = TableCommands.new.create_table(user: users(:erik)).table
    TableChat.default.forget(table.id)
    stub_connection current_user: users(:erik)

    subscribe waiting_table_id: table.id

    assert subscription.confirmed?
    assert_equal [ "chat_history" ], transmissions.map { |message| message["type"] }
  end
end
