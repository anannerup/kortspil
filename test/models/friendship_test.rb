require "test_helper"

class FriendshipTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  setup do
    @anna = users(:approved)
    @frida = users(:frida)
  end

  test "a request starts pending and becomes a friendship when accepted" do
    friendship = Friendship.create!(requester: @anna, addressee: @frida)

    assert friendship.pending?
    assert_not_includes @anna.friends, @frida

    friendship.accept!

    assert_includes @anna.friends, @frida
    assert_includes @frida.friends, @anna
  end

  test "the same request cannot be sent twice" do
    Friendship.create!(requester: @anna, addressee: @frida)
    duplicate = Friendship.new(requester: @anna, addressee: @frida)

    assert_not duplicate.save
    assert_includes duplicate.errors[:base], "Du har allerede sendt en venneanmodning til Frida"
  end

  test "a reverse request is refused while one is pending" do
    Friendship.create!(requester: @anna, addressee: @frida)
    reverse = Friendship.new(requester: @frida, addressee: @anna)

    assert_not reverse.save
    assert_includes reverse.errors[:base], "Anna har allerede sendt dig en venneanmodning"
  end

  test "friends cannot request each other again" do
    reverse = Friendship.new(requester: users(:admin), addressee: @anna)

    assert_not reverse.save
    assert_includes reverse.errors[:base], "I er allerede venner"
  end

  test "the database rejects a reverse duplicate pair" do
    Friendship.create!(requester: @anna, addressee: @frida)

    assert_raises ActiveRecord::RecordNotUnique do
      Friendship.new(requester: @frida, addressee: @anna).save!(validate: false)
    end
  end

  test "a user cannot befriend themself" do
    friendship = Friendship.new(requester: @anna, addressee: @anna)

    assert_not friendship.save
    assert_includes friendship.errors[:base], "Du kan ikke være ven med dig selv"
  end

  test "only approved users can be befriended" do
    %i[pending rejected blocked].each do |state|
      friendship = Friendship.new(requester: @anna, addressee: users(state))

      assert_not friendship.save, "#{state} user should not be befriendable"
    end
  end

  test "a new request notifies the addressee" do
    friendship = nil
    messages = capture_broadcasts(NotificationsChannel.broadcasting_for(@frida)) do
      friendship = Friendship.create!(requester: @anna, addressee: @frida)
    end

    assert_equal [ { "type" => "friend_request", "friendship_id" => friendship.id, "from" => "Anna" } ], messages
  end

  test "removing a user removes their friendships" do
    assert_difference -> { Friendship.count }, -2 do
      @anna.destroy!
    end
  end
end
