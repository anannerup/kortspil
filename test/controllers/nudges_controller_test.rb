require "test_helper"

# Request tests for puf (ticket 16): a seated player's puf and withdrawal from the
# bord's page, and the friend's answer from their notification.
class NudgesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @anna = users(:approved)
    @anders = users(:admin)
    @table = WaitingTable.set_up(user: @anna, kind: "private").table
  end

  test "the vært nudges a friend from the bord's page and gets the bord back with the puf" do
    sign_in_as @anna

    post waiting_table_nudges_path(@table), params: { friend_id: @anders.id }, as: :json

    assert_response :success
    assert_equal [ [ @anders.username, "pending" ] ], response.parsed_body.dig("table", "nudges").map { |nudge| nudge.values_at("name", "state") }

    delete waiting_table_nudge_path(@table, 1), as: :json
    assert_equal "withdrawn", response.parsed_body.dig("table", "nudges", 0, "state")
  end

  test "a seated player who is not the vært nudges their friend and may withdraw it" do
    erik = users(:erik)
    friendships(:erik_asks_anna).accept!
    Friendship.create!(requester: erik, addressee: @anders, state: :accepted)
    @table.nudge(user: @anna, friend: erik)
    @table.answer_nudge(user: erik, nudge_id: 1, accept: true)
    sign_in_as erik

    post waiting_table_nudges_path(@table), params: { friend_id: @anders.id }, as: :json

    assert_response :success
    nudge = response.parsed_body.dig("table", "nudges").find { |candidate| candidate["user_id"] == @anders.id }
    assert_equal [ "pending", erik.id ], nudge.values_at("state", "from_id")

    delete waiting_table_nudge_path(@table, nudge["id"]), as: :json
    assert_response :success
    assert_equal "withdrawn", response.parsed_body.dig("table", "nudges").find { |candidate| candidate["id"] == nudge["id"] }["state"]
  end

  test "the bord's page lists the vært's friends to nudge" do
    sign_in_as @anna

    get waiting_table_path(@table)

    friends = JSON.parse(css_select("div#root").first["data-friends"])
    assert_equal [ @anders.username ], friends.map { |friend| friend["username"] }
  end

  test "the friend accepts from the notification and is seated; the answer leads to the bord" do
    @table.nudge(user: @anna, friend: @anders)
    sign_in_as @anders

    patch waiting_table_nudge_path(@table, 1), params: { answer: "accept" }, as: :json

    assert_response :success
    assert_equal "/borde/#{@table.id}", response.parsed_body.dig("table", "path")
    assert @table.reload.seated?(@anders)
  end

  test "the friend declines, and a puf that is no longer valid is refused" do
    @table.nudge(user: @anna, friend: @anders)
    sign_in_as @anders

    patch waiting_table_nudge_path(@table, 1), params: { answer: "decline" }, as: :json
    assert_response :success
    assert_not @table.reload.seated?(@anders)

    patch waiting_table_nudge_path(@table, 1), params: { answer: "accept" }, as: :json
    assert_response :unprocessable_entity
    assert_equal "Det puf gælder ikke længere.", response.parsed_body["error"]
  end

  test "answering a puf to a bord that is gone says so" do
    sign_in_as @anders

    patch waiting_table_nudge_path("bgone12345", 1), params: { answer: "accept" }, as: :json

    assert_response :unprocessable_entity
    assert_equal "Det bord findes ikke længere.", response.parsed_body["error"]
  end
end
