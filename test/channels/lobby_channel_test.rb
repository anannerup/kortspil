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
end
