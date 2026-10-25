require "test_helper"

# Seam 2 for puf (ticket 16): the vært nudges friends to a bord before its
# spil. Driven through the bord's actions with a fake clock, asserted on
# their outcomes, the bord's entry (what the vært sees) and the notifications.
class NudgesTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  setup do
    @anna = users(:approved)
    @anders = users(:admin)
    @erik = users(:erik)
    @frida = users(:frida)
    friendships(:erik_asks_anna).accept!
    befriend(@anna, @frida)
    @clock = FakeClock.new
    @table = WaitingTable.set_up(user: @anna, surroundings:).table
  end

  test "the vært nudges a friend, who is told at once with the bord and who nudged" do
    outcome = nil
    assert_broadcasts(NotificationsChannel.broadcasting_for(@anders), 1) do
      outcome = @table.nudge(user: @anna, friend: @anders, surroundings:)
    end

    assert_not outcome.refused?
    nudge = outcome.table.nudge_for(@anders.id)
    assert_equal [ @anders.username, "pending", @clock.now + WaitingTable::NUDGE_LIFETIME ], [ nudge.name, nudge.state, nudge.expires_at ]
    message = JSON.parse(broadcasts(NotificationsChannel.broadcasting_for(@anders)).last)
    assert_equal [ "nudge", @table.id, "Annas bord", @anna.username, "/borde/#{@table.id}/nudges/#{nudge.id}" ],
      message.values_at("type", "table_id", "table_name", "from", "path")
  end

  test "only friends can be nudged, only by the vært, and not twice at once" do
    @table.sit(user: @erik, seat: 1, surroundings:)
    stranger = User.create!(username: "Gorm", email_address: "gorm@example.com", password: "password", approval_state: :approved)

    assert_equal :not_friend, @table.nudge(user: @anna, friend: stranger, surroundings:).refusal
    assert_equal :not_friend, @table.nudge(user: @anna, friend: nil, surroundings:).refusal
    assert_equal :not_host, @table.nudge(user: @erik, friend: @frida, surroundings:).refusal
    assert_equal :already_seated, @table.nudge(user: @anna, friend: @erik, surroundings:).refusal
    @table.nudge(user: @anna, friend: @frida, surroundings:)
    assert_equal :already_nudged, @table.nudge(user: @anna, friend: @frida, surroundings:).refusal
    assert_equal :practice_seats, (WaitingTable.set_up_practice(user: @frida, surroundings:).table).nudge(user: @frida, friend: @anna, surroundings:).refusal
  end

  test "the cap: pending pufs + seated players + bots never exceed four" do
    @table.add_bot(user: @anna, seat: 1, surroundings:)
    @table.nudge(user: @anna, friend: @anders, surroundings:)
    @table.nudge(user: @anna, friend: @erik, surroundings:)

    assert_equal :nudge_cap, @table.nudge(user: @anna, friend: @frida, surroundings:).refusal
    assert_equal :seat_reserved, @table.add_bot(user: @anna, seat: 2, surroundings:).refusal, "the free seats are held"
    assert_equal :seat_reserved, @table.sit(user: users(:blocked), seat: 2, surroundings:).refusal
    assert_equal 2, @table.reload.lobby_entry["reserved"]
  end

  test "a decline, an expiry or a withdrawal frees the slot for a new puf" do
    @table.add_bot(user: @anna, seat: 1, surroundings:)
    @table.add_bot(user: @anna, seat: 2, surroundings:)
    first = @table.nudge(user: @anna, friend: @anders, surroundings:).table.nudge_for(@anders.id)

    assert_equal :nudge_cap, @table.nudge(user: @anna, friend: @erik, surroundings:).refusal
    @table.answer_nudge(user: @anders, nudge_id: first.id, accept: false, surroundings:)
    second = @table.nudge(user: @anna, friend: @erik, surroundings:).table.nudge_for(@erik.id)

    assert_equal :nudge_cap, @table.nudge(user: @anna, friend: @frida, surroundings:).refusal
    @table.withdraw_nudge(user: @anna, nudge_id: second.id, surroundings:)
    @table.nudge(user: @anna, friend: @frida, surroundings:)

    @clock.advance(WaitingTable::NUDGE_LIFETIME)
    assert_not @table.nudge(user: @anna, friend: @anders, surroundings:).refused?, "Frida's puf expired"
    assert_equal({ @anders.username => "pending", @erik.username => "withdrawn", @frida.username => "expired" },
      states(@table), "the vært sees each puf's state")
  end

  test "pufs expire by the clock, and the friend is told the puf is gone" do
    @table.nudge(user: @anna, friend: @anders, surroundings:)
    @clock.advance(WaitingTable::NUDGE_LIFETIME - 1)
    @table.expire_nudges(surroundings:)
    assert_equal "pending", states(@table)[@anders.username]

    @clock.advance(1)
    assert_broadcasts(NotificationsChannel.broadcasting_for(@anders), 1) { @table.expire_nudges(surroundings:) }

    assert_equal "expired", states(@table)[@anders.username]
    assert_equal [ "nudge_gone", "expired" ], JSON.parse(broadcasts(NotificationsChannel.broadcasting_for(@anders)).last).values_at("type", "state")
    assert_equal :no_such_nudge, @table.answer_nudge(user: @anders, nudge_id: 1, accept: true, surroundings:).refusal
  end

  test "accepting seats the friend in a free seat, at a private or password bord without the password" do
    [ [ "private", nil ], [ "password", "hemmelig" ] ].each do |kind, password|
      @anna.current_table.leave(user: @anna, surroundings:)
      table = WaitingTable.set_up(user: @anna, kind:, password:, surroundings:).table
      table.add_bot(user: @anna, seat: 1, surroundings:)
      nudge = table.nudge(user: @anna, friend: @anders, surroundings:).table.nudge_for(@anders.id)

      outcome = table.answer_nudge(user: @anders, nudge_id: nudge.id, accept: true, surroundings:)

      assert_not outcome.refused?, kind
      assert_equal 2, table.reload.seat_of(@anders)
      assert_equal "accepted", states(table)[@anders.username]
      assert_equal table.id, @anders.current_table.id
      table.leave(user: @anders, surroundings:)
    end
  end

  test "only the nudged friend answers, and accepting waits while they sit at another bord" do
    nudge = @table.nudge(user: @anna, friend: @anders, surroundings:).table.nudge_for(@anders.id)
    other = WaitingTable.set_up(user: @anders, surroundings:).table

    assert_equal :no_such_nudge, @table.answer_nudge(user: @erik, nudge_id: nudge.id, accept: true, surroundings:).refusal
    assert_equal :seated_elsewhere, @table.answer_nudge(user: @anders, nudge_id: nudge.id, accept: true, surroundings:).refusal
    assert_equal "pending", states(@table)[@anders.username]

    other.leave(user: @anders, surroundings:)
    assert_not @table.answer_nudge(user: @anders, nudge_id: nudge.id, accept: true, surroundings:).refused?
  end

  test "a nudged friend who sits down by themself takes the held seat" do
    @table.add_bot(user: @anna, seat: 1, surroundings:)
    @table.add_bot(user: @anna, seat: 2, surroundings:)
    @table.nudge(user: @anna, friend: @anders, surroundings:)

    assert_not @table.sit(user: @anders, seat: 3, surroundings:).refused?
    assert_equal "accepted", states(@table)[@anders.username]
  end

  test "a seat held by a puf is not taken, so the spil starts once the friend has answered" do
    1.upto(2) { |seat| @table.add_bot(user: @anna, seat:, surroundings:) }
    nudge = @table.nudge(user: @anna, friend: @anders, surroundings:).table.nudge_for(@anders.id)
    assert_equal :seats_not_filled, @table.start(user: @anna, surroundings:).refusal

    @table.answer_nudge(user: @anders, nudge_id: nudge.id, accept: true, surroundings:)

    assert_not @table.start(user: @anna, surroundings:).refused?
    assert_empty WaitingTables.default.nudges_for(@anders)
    assert_equal :not_waiting, @table.nudge(user: @anna, friend: @erik, surroundings:).refusal
  end

  test "the bord's pending pufs are gone with it when its last human leaves" do
    @table.nudge(user: @anna, friend: @anders, surroundings:)

    assert_broadcasts(NotificationsChannel.broadcasting_for(@anders), 1) { @table.leave(user: @anna, surroundings:) }
    assert_equal "nudge_gone", JSON.parse(broadcasts(NotificationsChannel.broadcasting_for(@anders)).last)["type"]
    assert_empty WaitingTables.default.nudges_for(@anders)
  end

  private

  def surroundings = Table::Surroundings.new(scheduler: FakeScheduler.new, shuffler: Random.new(0), random: Random.new(0), clock: @clock)

  def befriend(user, other) = Friendship.create!(requester: user, addressee: other, state: :accepted)

  def states(table) = table.reload.lobby_entry["nudges"].to_h { |nudge| [ nudge["name"], nudge["state"] ] }
end
