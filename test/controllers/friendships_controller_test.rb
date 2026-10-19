require "test_helper"

class FriendshipsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @anna = users(:approved)
    sign_in_as @anna
  end

  test "the Konto sub-navigation links to the friends page and counts incoming requests" do
    get friendships_path

    assert_response :success
    assert_select "nav.konto-nav a[href='#{friendships_path}']", /Venner/
    assert_select "nav.konto-nav .badge", "1"
  end

  test "the friends page lists friends with presence, incoming and outgoing requests" do
    users(:admin).mark_online!
    Friendship.create!(requester: @anna, addressee: users(:frida))

    get friendships_path

    assert_select "#friends li", 1
    assert_select "#friends li", /Anders.*Online/m
    assert_select "#friends .presence.online"
    assert_select "#incoming-requests li", /Erik/
    assert_select "#outgoing-requests li", /Frida/
  end

  test "an offline friend is shown as offline" do
    get friendships_path

    assert_select "#friends li", /Offline/
    assert_select "#friends .presence.online", 0
  end

  test "search lists approved strangers and excludes self, friends and unapproved users" do
    get friendships_path, params: { q: "a" }

    assert_select "#search-results li", /Frida/
    assert_select "#search-results li", text: /Anna|Anders|Erik|Bodil|Carl|Dorte/, count: 0
  end

  test "sending a request" do
    assert_difference -> { Friendship.pending.count } do
      post friendships_path, params: { addressee_id: users(:frida).id }
    end

    assert_redirected_to friendships_path
    assert_equal "Venneanmodning sendt til Frida", flash[:notice]
  end

  test "a reverse duplicate request is refused" do
    assert_no_difference -> { Friendship.count } do
      post friendships_path, params: { addressee_id: users(:erik).id }
    end

    assert_equal "Erik har allerede sendt dig en venneanmodning", flash[:alert]
  end

  test "an unapproved user cannot be sent a request" do
    assert_no_difference -> { Friendship.count } do
      post friendships_path, params: { addressee_id: users(:pending).id }
    end

    assert_equal "Brugeren kan ikke findes", flash[:alert]
  end

  test "accepting an incoming request" do
    friendship = friendships(:erik_asks_anna)

    patch friendship_path(friendship)

    assert friendship.reload.accepted?
    assert_includes @anna.friends, users(:erik)
  end

  test "only the addressee can accept" do
    friendship = Friendship.create!(requester: @anna, addressee: users(:frida))

    patch friendship_path(friendship)

    assert_response :not_found
    assert friendship.reload.pending?
  end

  test "declining an incoming request deletes it" do
    delete friendship_path(friendships(:erik_asks_anna))

    assert_not Friendship.exists?(friendships(:erik_asks_anna).id)
    assert_equal "Venneanmodningen fra Erik er afvist", flash[:notice]
  end

  test "withdrawing an outgoing request deletes it" do
    friendship = Friendship.create!(requester: @anna, addressee: users(:frida))

    delete friendship_path(friendship)

    assert_not Friendship.exists?(friendship.id)
    assert_equal "Venneanmodningen til Frida er trukket tilbage", flash[:notice]
  end

  test "removing a friend deletes the friendship for both" do
    delete friendship_path(friendships(:anna_and_anders))

    assert_not_includes @anna.friends, users(:admin)
    assert_not_includes users(:admin).friends, @anna
    assert_equal "Anders er fjernet fra dine venner", flash[:notice]
  end

  test "another user's friendship cannot be deleted" do
    friendship = Friendship.create!(requester: users(:erik), addressee: users(:frida))

    delete friendship_path(friendship)

    assert_response :not_found
    assert Friendship.exists?(friendship.id)
  end

  test "a pending user cannot reach the friends page" do
    sign_out
    sign_in_as users(:pending)

    get friendships_path

    assert_redirected_to approval_path
  end
end
