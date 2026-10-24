require "test_helper"

class LobbyChannelTest < ActionCable::Channel::TestCase
  test "subscribing streams the lobby and sends the open tables" do
    table = TableCommands.new.create_table(user: users(:erik)).table
    stub_connection current_user: users(:approved)

    subscribe

    assert subscription.confirmed?
    assert_has_stream LobbyChannel::STREAM
    assert_equal [ table.id ], transmissions.last["tables"].map { |entry| entry["id"] }
  end

  test "a waiting room follows its own table, private ones included" do
    table = TableCommands.new.create_table(user: users(:erik), kind: "private").table
    stub_connection current_user: users(:approved)

    subscribe table_id: table.id

    assert subscription.confirmed?
    assert_has_stream LobbyChannel.table_stream(table)
    assert_equal [ "table", table.id ], [ transmissions.last["type"], transmissions.last["table"]["id"] ]
  end

  test "a practice table has no waiting room" do
    table = TableCommands.new.start_practice(user: users(:erik)).table
    stub_connection current_user: users(:approved)

    subscribe table_id: table.id

    assert subscription.rejected?
  end
end
