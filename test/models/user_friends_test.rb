require "test_helper"

class UserFriendsTest < ActiveSupport::TestCase
  setup do
    @anna = users(:approved)
  end

  test "search finds approved users by part of their username, case-insensitively" do
    assert_equal [ users(:frida) ], @anna.befriendable_users("FRI").to_a
  end

  test "search excludes self, friends, pending requests and unapproved users" do
    results = @anna.befriendable_users("a")

    assert_not_includes results, @anna
    assert_not_includes results, users(:admin) # friend
    assert_not_includes results, users(:erik) # has asked Anna
    assert_not_includes results, users(:pending)
    assert_not_includes results, users(:blocked)
    assert_includes results, users(:frida)
  end

  test "an empty search finds nobody" do
    assert_empty @anna.befriendable_users(" ")
  end

  test "search treats LIKE wildcards literally" do
    assert_empty @anna.befriendable_users("%")
  end

  test "online while last seen within the online window" do
    travel_to Time.current do
      @anna.mark_online!
      assert @anna.online?
      assert_includes User.online, @anna

      travel User::ONLINE_WINDOW + 1.second
      assert_not @anna.reload.online?
      assert_not_includes User.online, @anna
    end
  end

  test "marking offline ends presence at once" do
    @anna.mark_online!
    @anna.mark_offline!

    assert_not @anna.reload.online?
  end
end
