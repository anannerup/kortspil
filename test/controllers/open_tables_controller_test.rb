require "test_helper"

# Request tests for open tables (ticket 12): creating one from the lobby,
# sitting, starting, standing up, and each bord's own URL: /borde/:id
# before the start (in memory), /tables/:id once stored.
class OpenTablesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @host = users(:approved)
  end

  test "Opret bord creates an open table with the chosen rules and opens its waiting page" do
    sign_in_as @host

    assert_no_difference %w[ Table.count Seat.count Game.count ] do
      post waiting_tables_path, params: { game: "hjerterfri", rules: { end_score: "60", queen_breaks_hearts: "1", jack_of_diamonds_minus_ten: "0", shooters_choice: "0" } }
    end

    table = @host.current_table
    assert table.open?
    assert_equal "hjerterfri", table.game
    assert_equal Hjerterfri::Rules.new(end_score: 60, queen_breaks_hearts: true), table.rules.game
    assert_redirected_to waiting_table_path(table)
    follow_redirect!
    assert_select "div#root[data-page=waiting]" do |root|
      assert_equal table.id, JSON.parse(root.first["data-table"])["id"]
    end
  end

  test "a game that does not exist cannot be chosen" do
    sign_in_as @host

    post waiting_tables_path, params: { game: "bridge" }

    assert_redirected_to root_path
    assert_equal "Det spil findes ikke.", flash[:alert]
    assert_nil @host.current_table
  end

  test "the lobby lists the open tables" do
    table = WaitingTable.set_up(user: users(:erik)).table
    sign_in_as @host

    get root_path

    assert_select "div#root[data-page=lobby]" do |root|
      assert_equal [ table.id ], JSON.parse(root.first["data-tables"]).map { |entry| entry["id"] }
    end
  end

  test "another player opens the table's URL, picks a seat and sits down" do
    table = WaitingTable.set_up(user: @host).table
    sign_in_as users(:erik)

    get waiting_table_path(table)
    assert_select "div#root[data-page=waiting]"

    post waiting_table_seat_path(table), params: { position: 2 }

    assert_redirected_to waiting_table_path(table)
    assert_equal 2, table.reload.seating.seat_of(users(:erik))
  end

  test "sitting at a second table is refused with a clear message" do
    WaitingTable.set_up(user: @host)
    other = WaitingTable.set_up(user: users(:erik)).table
    sign_in_as @host

    post waiting_table_seat_path(other), params: { position: 1 }, headers: { "HTTP_REFERER" => root_url }

    assert_redirected_to root_url
    assert_equal "Du sidder allerede ved et andet bord. Forlad det, før du sætter dig et nyt sted.", flash[:alert]
    assert_not other.seated?(@host)
  end

  test "Øvebord is refused while the player sits at a table" do
    WaitingTable.set_up(user: @host)
    sign_in_as @host

    post practice_tables_path

    assert_redirected_to root_path
    assert_match "Du sidder allerede ved et andet bord", flash[:alert]
    assert_not @host.current_table.practice?
  end

  test "the vært starts once all four have sat down, and the table page opens for the players" do
    table = WaitingTable.set_up(user: @host).table
    sign_in_as @host

    post waiting_table_start_path(table)
    assert_equal "Spillet kan først starte, når alle fire pladser er besat.", flash[:alert]

    [ users(:admin), users(:erik), users(:frida) ].each.with_index(1) { |user, seat| table.sit(user:, seat:) }
    assert_difference -> { Table.count } do
      post waiting_table_start_path(table)
    end

    stored = Table.last
    assert_redirected_to table_path(stored)
    assert stored.playing?
    follow_redirect!
    assert_select "div#root[data-page=table][data-table-id=?]", stored.id.to_s

    get waiting_table_path(table)
    assert_redirected_to table_path(stored), "the bord's old link leads to its spil"
  end

  test "a bord that is gone (closed, or dropped by a restart) sends its visitors back to the lobby" do
    sign_in_as @host

    get waiting_table_path("bgone12345")

    assert_redirected_to root_path
    assert_equal "Det bord findes ikke længere.", flash[:alert]
  end

  test "a player who does not sit at a started table is sent back to the lobby" do
    table = WaitingTable.set_up(user: @host).table
    [ users(:admin), users(:erik), users(:frida) ].each.with_index(1) { |user, seat| table.sit(user:, seat:) }
    table = table.start(user: @host).table
    sign_in_as User.create!(username: "Gorm", email_address: "gorm@example.com", password: "password", approval_state: :approved)

    get table_path(table)

    assert_redirected_to root_path
    assert_equal "Spillet ved det bord er allerede i gang.", flash[:alert]
  end

  test "Rejs dig before the start frees the seat and goes back to the lobby" do
    table = WaitingTable.set_up(user: @host).table
    table.sit(user: users(:erik), seat: 1)
    sign_in_as users(:erik)

    post waiting_table_departure_path(table)

    assert_redirected_to root_path
    assert_not table.reload.seated?(users(:erik))
    assert table.reload.waiting?
  end
end
