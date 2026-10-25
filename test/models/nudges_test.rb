require "test_helper"

# Seam 2 for puf (ticket 16): the vært nudges friends to a bord before its
# spil. Driven through TableCommands with a fake clock, asserted on its
# outcomes, the bord's entry (what the vært sees) and the notifications.
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
    @table = commands.create_table(user: @anna).table
  end

  test "the vært nudges a friend, who is told at once with the bord and who nudged" do
    outcome = nil
    assert_broadcasts(NotificationsChannel.broadcasting_for(@anders), 1) do
      outcome = commands.nudge(table: @table, user: @anna, friend: @anders)
    end

    assert_not outcome.refused?
    nudge = outcome.table.nudge_for(@anders.id)
    assert_equal [ @anders.username, "pending", @clock.now + WaitingTable::NUDGE_LIFETIME ], [ nudge.name, nudge.state, nudge.expires_at ]
    message = JSON.parse(broadcasts(NotificationsChannel.broadcasting_for(@anders)).last)
    assert_equal [ "nudge", @table.id, "Annas bord", @anna.username, "/borde/#{@table.id}/nudges/#{nudge.id}" ],
      message.values_at("type", "table_id", "table_name", "from", "path")
  end

  test "only friends can be nudged, only by the vært, and not twice at once" do
    commands.sit(table: @table, user: @erik, seat: 1)
    stranger = User.create!(username: "Gorm", email_address: "gorm@example.com", password: "password", approval_state: :approved)

    assert_equal :not_friend, commands.nudge(table: @table, user: @anna, friend: stranger).refusal
    assert_equal :not_friend, commands.nudge(table: @table, user: @anna, friend: nil).refusal
    assert_equal :not_host, commands.nudge(table: @table, user: @erik, friend: @frida).refusal
    assert_equal :already_seated, commands.nudge(table: @table, user: @anna, friend: @erik).refusal
    commands.nudge(table: @table, user: @anna, friend: @frida)
    assert_equal :already_nudged, commands.nudge(table: @table, user: @anna, friend: @frida).refusal
    assert_equal :practice_seats, commands.nudge(table: commands.start_practice(user: @frida).table, user: @frida, friend: @anna).refusal
  end

  test "the cap: pending pufs + seated players + bots never exceed four" do
    commands.add_bot(table: @table, user: @anna, seat: 1)
    commands.nudge(table: @table, user: @anna, friend: @anders)
    commands.nudge(table: @table, user: @anna, friend: @erik)

    assert_equal :nudge_cap, commands.nudge(table: @table, user: @anna, friend: @frida).refusal
    assert_equal :seat_reserved, commands.add_bot(table: @table, user: @anna, seat: 2).refusal, "the free seats are held"
    assert_equal :seat_reserved, commands.sit(table: @table, user: users(:blocked), seat: 2).refusal
    assert_equal 2, @table.reload.lobby_entry["reserved"]
  end

  test "a decline, an expiry or a withdrawal frees the slot for a new puf" do
    commands.add_bot(table: @table, user: @anna, seat: 1)
    commands.add_bot(table: @table, user: @anna, seat: 2)
    first = commands.nudge(table: @table, user: @anna, friend: @anders).table.nudge_for(@anders.id)

    assert_equal :nudge_cap, commands.nudge(table: @table, user: @anna, friend: @erik).refusal
    commands.answer_nudge(table: @table, user: @anders, nudge_id: first.id, accept: false)
    second = commands.nudge(table: @table, user: @anna, friend: @erik).table.nudge_for(@erik.id)

    assert_equal :nudge_cap, commands.nudge(table: @table, user: @anna, friend: @frida).refusal
    commands.withdraw_nudge(table: @table, user: @anna, nudge_id: second.id)
    commands.nudge(table: @table, user: @anna, friend: @frida)

    @clock.advance(WaitingTable::NUDGE_LIFETIME)
    assert_not commands.nudge(table: @table, user: @anna, friend: @anders).refused?, "Frida's puf expired"
    assert_equal({ @anders.username => "pending", @erik.username => "withdrawn", @frida.username => "expired" },
      states(@table), "the vært sees each puf's state")
  end

  test "pufs expire by the clock, and the friend is told the puf is gone" do
    commands.nudge(table: @table, user: @anna, friend: @anders)
    @clock.advance(WaitingTable::NUDGE_LIFETIME - 1)
    commands.expire_nudges(table: @table)
    assert_equal "pending", states(@table)[@anders.username]

    @clock.advance(1)
    assert_broadcasts(NotificationsChannel.broadcasting_for(@anders), 1) { commands.expire_nudges(table: @table) }

    assert_equal "expired", states(@table)[@anders.username]
    assert_equal [ "nudge_gone", "expired" ], JSON.parse(broadcasts(NotificationsChannel.broadcasting_for(@anders)).last).values_at("type", "state")
    assert_equal :no_such_nudge, commands.answer_nudge(table: @table, user: @anders, nudge_id: 1, accept: true).refusal
  end

  test "accepting seats the friend in a free seat, at a private or password bord without the password" do
    [ [ "private", nil ], [ "password", "hemmelig" ] ].each do |kind, password|
      commands.leave(table: @anna.current_table, user: @anna)
      table = commands.create_table(user: @anna, kind:, password:).table
      commands.add_bot(table:, user: @anna, seat: 1)
      nudge = commands.nudge(table:, user: @anna, friend: @anders).table.nudge_for(@anders.id)

      outcome = commands.answer_nudge(table:, user: @anders, nudge_id: nudge.id, accept: true)

      assert_not outcome.refused?, kind
      assert_equal 2, table.reload.seat_of(@anders)
      assert_equal "accepted", states(table)[@anders.username]
      assert_equal table.id, @anders.current_table.id
      commands.leave(table:, user: @anders)
    end
  end

  test "only the nudged friend answers, and accepting waits while they sit at another bord" do
    nudge = commands.nudge(table: @table, user: @anna, friend: @anders).table.nudge_for(@anders.id)
    other = commands.create_table(user: @anders).table

    assert_equal :no_such_nudge, commands.answer_nudge(table: @table, user: @erik, nudge_id: nudge.id, accept: true).refusal
    assert_equal :seated_elsewhere, commands.answer_nudge(table: @table, user: @anders, nudge_id: nudge.id, accept: true).refusal
    assert_equal "pending", states(@table)[@anders.username]

    commands.leave(table: other, user: @anders)
    assert_not commands.answer_nudge(table: @table, user: @anders, nudge_id: nudge.id, accept: true).refused?
  end

  test "a nudged friend who sits down by themself takes the held seat" do
    commands.add_bot(table: @table, user: @anna, seat: 1)
    commands.add_bot(table: @table, user: @anna, seat: 2)
    commands.nudge(table: @table, user: @anna, friend: @anders)

    assert_not commands.sit(table: @table, user: @anders, seat: 3).refused?
    assert_equal "accepted", states(@table)[@anders.username]
  end

  test "a seat held by a puf is not taken, so the spil starts once the friend has answered" do
    1.upto(2) { |seat| commands.add_bot(table: @table, user: @anna, seat:) }
    nudge = commands.nudge(table: @table, user: @anna, friend: @anders).table.nudge_for(@anders.id)
    assert_equal :seats_not_filled, commands.start(table: @table, user: @anna).refusal

    commands.answer_nudge(table: @table, user: @anders, nudge_id: nudge.id, accept: true)

    assert_not commands.start(table: @table, user: @anna).refused?
    assert_empty WaitingTables.default.nudges_for(@anders)
    assert_equal :not_waiting, commands.nudge(table: @table, user: @anna, friend: @erik).refusal
  end

  test "the bord's pending pufs are gone with it when its last human leaves" do
    commands.nudge(table: @table, user: @anna, friend: @anders)

    assert_broadcasts(NotificationsChannel.broadcasting_for(@anders), 1) { commands.leave(table: @table, user: @anna) }
    assert_equal "nudge_gone", JSON.parse(broadcasts(NotificationsChannel.broadcasting_for(@anders)).last)["type"]
    assert_empty WaitingTables.default.nudges_for(@anders)
  end

  private

  def commands = TableCommands.new(scheduler: FakeScheduler.new, shuffler: Random.new(0), random: Random.new(0), clock: @clock)

  def befriend(user, other) = Friendship.create!(requester: user, addressee: other, state: :accepted)

  def states(table) = table.reload.lobby_entry["nudges"].to_h { |nudge| [ nudge["name"], nudge["state"] ] }
end
