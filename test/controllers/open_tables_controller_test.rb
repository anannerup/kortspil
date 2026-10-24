require "test_helper"

# Request tests for open tables (ticket 12): creating one from the lobby,
# sitting, starting, standing up, and each table's own URL.
class OpenTablesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @host = users(:approved)
  end

  test "Opret bord creates an open table with the chosen rules and opens its waiting page" do
    sign_in_as @host

    assert_difference -> { Table.count } => 1, -> { Game.count } => 0 do
      post tables_path, params: { rules: { end_score: "60", queen_breaks_hearts: "1", jack_of_diamonds_minus_ten: "0", shooters_choice: "0" } }
    end

    table = Table.last
    assert table.open?
    assert_equal Hjerterfri::Rules.new(end_score: 60, queen_breaks_hearts: true), table.engine_rules
    assert_redirected_to table_path(table)
    follow_redirect!
    assert_select "div#root[data-page=waiting]" do |root|
      assert_equal table.id, JSON.parse(root.first["data-table"])["id"]
    end
  end

  test "the lobby lists the open tables" do
    table = TableCommands.new.create_table(user: users(:erik)).table
    sign_in_as @host

    get root_path

    assert_select "div#root[data-page=lobby]" do |root|
      assert_equal [ table.id ], JSON.parse(root.first["data-tables"]).map { |entry| entry["id"] }
    end
  end

  test "another player opens the table's URL, picks a seat and sits down" do
    table = TableCommands.new.create_table(user: @host).table
    sign_in_as users(:erik)

    get table_path(table)
    assert_select "div#root[data-page=waiting]"

    post table_seat_path(table), params: { position: 2 }

    assert_redirected_to table_path(table)
    assert_equal 2, table.seating.seat_of(users(:erik))
  end

  test "sitting at a second table is refused with a clear message" do
    TableCommands.new.create_table(user: @host)
    other = TableCommands.new.create_table(user: users(:erik)).table
    sign_in_as @host

    post table_seat_path(other), params: { position: 1 }, headers: { "HTTP_REFERER" => root_url }

    assert_redirected_to root_url
    assert_equal "Du sidder allerede ved et andet bord. Forlad det, før du sætter dig et nyt sted.", flash[:alert]
    assert_not other.seated?(@host)
  end

  test "Øvebord is refused while the player sits at a table" do
    TableCommands.new.create_table(user: @host)
    sign_in_as @host

    assert_no_difference -> { Table.count } do
      post practice_tables_path
    end
    assert_redirected_to root_path
    assert_match "Du sidder allerede ved et andet bord", flash[:alert]
  end

  test "the vært starts once all four have sat down, and the table page opens for the players" do
    table = TableCommands.new.create_table(user: @host).table
    sign_in_as @host

    post table_start_path(table)
    assert_equal "Spillet kan først starte, når alle fire pladser er besat.", flash[:alert]

    [ users(:admin), users(:erik), users(:frida) ].each.with_index(1) { |user, seat| TableCommands.new.sit(table:, user:, seat:) }
    post table_start_path(table)

    assert_redirected_to table_path(table)
    assert table.reload.playing?
    follow_redirect!
    assert_select "div#root[data-page=table][data-table-id=?]", table.id.to_s
  end

  test "a player who does not sit at a started table is sent back to the lobby" do
    table = TableCommands.new.create_table(user: @host).table
    [ users(:admin), users(:erik), users(:frida) ].each.with_index(1) { |user, seat| TableCommands.new.sit(table:, user:, seat:) }
    TableCommands.new.start(table:, user: @host)
    sign_in_as User.create!(username: "Gorm", email_address: "gorm@example.com", password: "password", approval_state: :approved)

    get table_path(table)

    assert_redirected_to root_path
    assert_equal "Spillet ved det bord er allerede i gang.", flash[:alert]
  end

  test "Rejs dig before the start frees the seat and goes back to the lobby" do
    table = TableCommands.new.create_table(user: @host).table
    TableCommands.new.sit(table:, user: users(:erik), seat: 1)
    sign_in_as users(:erik)

    post table_departure_path(table)

    assert_redirected_to root_path
    assert_not table.seated?(users(:erik))
    assert table.reload.waiting?
  end
end
