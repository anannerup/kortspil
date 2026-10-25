require "test_helper"

class LobbyChannelTest < ActionCable::Channel::TestCase
  test "subscribing streams the lobby and sends the open tables" do
    table = WaitingTable.set_up(user: users(:erik)).table
    stub_connection current_user: users(:approved)

    subscribe

    assert subscription.confirmed?
    assert_has_stream LobbyChannel::STREAM
    assert_equal [ table.id ], transmissions.last["tables"].map { |entry| entry["id"] }
  end

  test "a bord's page follows its own bord before the start, private ones included, and asks for pufs to expire" do
    table = WaitingTable.set_up(user: users(:erik), kind: "private").table
    stub_connection current_user: users(:approved)

    subscribe waiting_table_id: table.id

    assert subscription.confirmed?
    assert_has_stream LobbyChannel.waiting_table_stream(table.id)
    assert_equal [ "table", table.id ], [ transmissions.last["type"], transmissions.last["table"]["id"] ]
    assert_nothing_raised { perform :expire_nudges }
  end

  test "a practice bord has no page to follow, nor has a bord that is gone" do
    table = WaitingTable.set_up_practice(user: users(:erik)).table
    stub_connection current_user: users(:approved)

    subscribe waiting_table_id: table.id
    assert subscription.rejected?

    subscribe waiting_table_id: "bgone12345"
    assert subscription.rejected?
  end
end
