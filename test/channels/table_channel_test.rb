require "test_helper"

class TableChannelTest < ActionCable::Channel::TestCase
  setup do
    @user = users(:approved)
    @table = TableCommands.new.start_practice(user: @user).table
  end

  test "a seated user subscribes to their own stream, gets the state and can play" do
    stub_connection current_user: @user

    subscribe table_id: @table.id

    assert subscription.confirmed?
    assert_has_stream TableChannel.stream_name(@table.id, @user.id)
    assert_equal "state", transmissions.last["type"]

    assert_broadcasts(TableChannel.stream_name(@table.id, @user.id), 1) do
      perform :play, card: "AH"
    end
  end

  test "a user who does not sit at the table is rejected" do
    stub_connection current_user: users(:admin)

    subscribe table_id: @table.id

    assert subscription.rejected?
  end
end
