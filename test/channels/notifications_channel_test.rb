require "test_helper"

class NotificationsChannelTest < ActionCable::Channel::TestCase
  setup do
    @anna = users(:approved)
    stub_connection current_user: @anna
  end

  test "subscribing streams the user's notifications and marks them online" do
    subscribe

    assert subscription.confirmed?
    assert_has_stream_for @anna
    assert @anna.reload.online?
  end

  test "unsubscribing marks the user offline" do
    subscribe
    unsubscribe

    assert_not @anna.reload.online?
  end

  test "the heartbeat keeps the user online past the online window" do
    subscribe
    heartbeat, options = NotificationsChannel.periodic_timers.sole

    travel User::ONLINE_WINDOW - 1.second do
      subscription.instance_exec(&heartbeat)
    end

    travel User::ONLINE_WINDOW + 10.seconds do
      assert @anna.reload.online?
    end
    assert_equal NotificationsChannel::HEARTBEAT_INTERVAL, options[:every]
  end

  test "a friend request reaches the addressee's stream" do
    subscribe

    friendship = nil
    messages = capture_broadcasts(NotificationsChannel.broadcasting_for(@anna)) do
      friendship = Friendship.create!(requester: users(:frida), addressee: @anna)
    end

    assert_equal [ { "type" => "friend_request", "friendship_id" => friendship.id, "from" => "Frida" } ], messages
  end
end
