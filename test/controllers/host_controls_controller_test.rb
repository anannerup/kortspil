require "test_helper"

# Request tests for host controls and table types (tickets 13 and 14):
# the vært's kick, bot and settings forms, creating password and private
# tables, and sitting at a password table.
class HostControlsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @host = users(:approved)
    @erik = users(:erik)
  end

  test "the vært kicks a player and adds and removes a bot" do
    table = TableCommands.new.create_table(user: @host).table
    TableCommands.new.sit(table:, user: @erik, seat: 1)
    sign_in_as @host

    post table_kick_path(table), params: { position: 1 }
    assert_redirected_to table_path(table)
    assert_not table.seated?(@erik)

    post table_bot_path(table), params: { position: 2 }
    assert table.seating.occupants.fetch(2).bot?

    delete table_bot_path(table), params: { position: 2 }
    assert table.seating.occupants.fetch(2).empty?
  end

  test "a player who is not the vært is refused the vært's controls" do
    table = TableCommands.new.create_table(user: @host).table
    TableCommands.new.sit(table:, user: @erik, seat: 1)
    sign_in_as @erik

    post table_bot_path(table), params: { position: 2 }, headers: { "HTTP_REFERER" => table_url(table) }

    assert_redirected_to table_url(table)
    assert_equal "Det kan kun værten.", flash[:alert]
    assert table.seating.occupants.fetch(2).empty?
  end

  test "the vært changes the rules and makes the table private" do
    table = TableCommands.new.create_table(user: @host).table
    sign_in_as @host

    patch table_settings_path(table), params: { kind: "private", rules: { end_score: "25", queen_breaks_hearts: "0", jack_of_diamonds_minus_ten: "1", shooters_choice: "0" } }

    assert_redirected_to table_path(table)
    table.reload
    assert table.private?
    assert_equal Hjerterfri::Rules.new(end_score: 25, jack_of_diamonds_minus_ten: true), table.engine_rules
  end

  test "Opret bord makes a password table, and sitting there takes the password" do
    sign_in_as @host
    post tables_path, params: { kind: "password", password: "hemmelig" }
    table = Table.last
    assert table.password?

    sign_in_as @erik
    get root_path
    assert_select "div#root[data-page=lobby]" do |root|
      assert_equal [ "password" ], JSON.parse(root.first["data-tables"]).map { |entry| entry["kind"] }
    end

    post table_seat_path(table), params: { position: 1, password: "forkert" }, headers: { "HTTP_REFERER" => root_url }
    assert_redirected_to root_url
    assert_equal "Forkert adgangskode.", flash[:alert]
    assert_not table.seated?(@erik)

    post table_seat_path(table), params: { position: 1, password: "hemmelig" }
    assert_redirected_to table_path(table)
    assert table.seated?(@erik)
  end

  test "a password table without a password is refused" do
    sign_in_as @host

    assert_no_difference -> { Table.count } do
      post tables_path, params: { kind: "password", password: "" }
    end
    assert_equal "Skriv en adgangskode til bordet.", flash[:alert]
  end

  test "a private table is missing from the lobby, but its link opens the waiting room for anyone" do
    sign_in_as @host
    post tables_path, params: { kind: "private" }
    table = Table.last
    assert table.private?

    sign_in_as @erik
    get root_path
    assert_select "div#root[data-page=lobby]" do |root|
      assert_empty JSON.parse(root.first["data-tables"])
    end

    get table_path(table)
    assert_select "div#root[data-page=waiting]"
    post table_seat_path(table), params: { position: 3 }
    assert_equal 3, table.seating.seat_of(@erik)
  end
end
