require "test_helper"

# Who sits where at a bord: occupants, takeovers and the seat_log, and the
# indexed "where does this user sit" query.
class Table::SeatingTest < ActiveSupport::TestCase
  setup do
    @user = users(:approved)
    @table = Table.create!(host: @user, kind: :practice, status: :playing)
  end

  test "a bord has four empty seats before anyone sits and before any spil" do
    seating = @table.seating

    assert_equal [ 0, 1, 2, 3 ], seating.occupants.map(&:seat)
    assert seating.occupants.all?(&:empty?)
    assert_nil seating.seat_of(@user)
    assert_raises(ArgumentError) { seating.snapshot }
  end

  test "a practice bord seats the user in seat 0 and bots in the rest, before a spil starts" do
    seating = @table.seating.seat_practice!(@user)

    assert_empty @table.games
    assert_equal 0, seating.seat_of(@user)
    assert_nil seating.seat_of(users(:admin))
    assert_equal [ [ @user.username, true, false ], [ "Bot 1", false, true ], [ "Bot 2", false, true ], [ "Bot 3", false, true ] ],
      seating.occupants.map { |occupant| [ occupant.name, occupant.human?, occupant.bot? ] }
    assert_equal [ { "kind" => "human", "user_id" => @user.id }, *(1..3).map { |n| { "kind" => "bot", "name" => "Bot #{n}" } } ],
      seating.snapshot
    assert @table.seated?(@user)
    assert_not @table.seated?(users(:admin))
  end

  test "a seat holds one occupant, and a bord one row per seat" do
    @table.seating.seat_practice!(@user)

    assert_raises(ActiveRecord::RecordInvalid) { Seat.create!(table: @table, position: 0, user: users(:admin)) }
    assert_not Seat.new(table: @table, position: 4, user: users(:admin)).valid?
    assert_not Seat.new(table: Table.create!(host: @user, kind: :practice), position: 0, user: @user, bot_name: "Bot 1").valid?
  end

  test "a bot takes over a human's seat and the change is appended to the spil's seat_log" do
    game = start_spil
    snapshot = game.seats

    seating = @table.seating.take_over!(0, game:, at_play: 17)

    assert_nil seating.seat_of(@user)
    assert seating.occupants.fetch(0).bot?
    assert_equal "Bot 4", seating.occupants.fetch(0).name, "a name no other bot at the bord has"
    assert_equal [ { "seat" => 0, "from" => @user.id, "to" => "Bot 4", "at_play" => 17 } ], game.reload.seat_log
    assert_equal snapshot, game.seats, "the start snapshot does not change"
    assert_not @table.seated?(@user)
    assert_raises(ArgumentError) { seating.take_over!(1, game:, at_play: 18) }
  end

  test "a player who has forladt a spil may not return to it, but that spil only" do
    game = start_spil
    seating = @table.seating
    assert_not seating.forladt?(@user, game)

    assert seating.take_over!(0, game:, at_play: 0).forladt?(@user, game.reload)

    next_spil = @table.games.create!(rules: {}, seats: game.seats)
    assert_not seating.forladt?(@user, next_spil)
    next_spil.update!(forfeited_by: @user)
    assert seating.forladt?(@user, next_spil), "leaving with \"Forlad bordet\" counts too"
  end

  test "the user's current bord is their latest seat at a bord that is not closed, in one indexed query" do
    assert_nil @user.current_table

    @table.seating.seat_practice!(@user)
    newer = Table.create!(host: @user, kind: :practice, status: :playing)
    newer.seating.seat_practice!(@user)
    assert_queries_count(1) { assert_equal newer, @user.current_table }
    assert_nil users(:admin).current_table

    newer.closed!
    assert_equal @table, @user.current_table
    assert_match "index_seats_on_user_id", Table.with_seated(@user).explain.inspect
  end

  private

  def start_spil
    seating = @table.seating.seat_practice!(@user)
    @table.games.create!(rules: {}, seats: seating.snapshot)
  end
end
