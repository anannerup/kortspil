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
    table = WaitingTable.set_up(user: @host).table
    table.sit(user: @erik, seat: 1)
    sign_in_as @host

    post waiting_table_kick_path(table), params: { position: 1 }
    assert_redirected_to waiting_table_path(table)
    assert_not table.reload.seated?(@erik)

    post waiting_table_bot_path(table), params: { position: 2 }
    assert table.reload.seating.occupants.fetch(2).bot?

    delete waiting_table_bot_path(table), params: { position: 2 }
    assert table.reload.seating.occupants.fetch(2).empty?
  end

  test "a player who is not the vært is refused the vært's controls" do
    table = WaitingTable.set_up(user: @host).table
    table.sit(user: @erik, seat: 1)
    sign_in_as @erik

    post waiting_table_bot_path(table), params: { position: 2 }, headers: { "HTTP_REFERER" => waiting_table_url(table) }

    assert_redirected_to waiting_table_url(table)
    assert_equal "Det kan kun værten.", flash[:alert]
    assert table.reload.seating.occupants.fetch(2).empty?
  end

  test "the table page sends its changes as JSON and gets the bord back, or why not" do
    table = WaitingTable.set_up(user: @host).table
    sign_in_as @host

    post waiting_table_bot_path(table), params: { position: 2 }, as: :json
    assert_response :success
    assert_equal [ @host.username, nil, "Bot 1", nil ], response.parsed_body.dig("table", "seats").map { |seat| seat["name"] }

    post waiting_table_start_path(table), as: :json
    assert_response :unprocessable_entity
    assert_equal "Spillet kan først starte, når alle fire pladser er besat.", response.parsed_body["error"]

    patch waiting_table_settings_path(table), params: { kind: "password", rules: { end_score: "100" } }, as: :json
    assert_response :unprocessable_entity
    assert_equal "Skriv en adgangskode til bordet.", response.parsed_body["error"]
    assert table.reload.open?
  end

  test "the vært starts from the table page once every seat is taken, and only then is there a spil" do
    table = WaitingTable.set_up(user: @host).table
    table.sit(user: @erik, seat: 1)
    [ 2, 3 ].each { |seat| table.add_bot(user: @host, seat:) }
    assert_equal 0, Table.count
    sign_in_as @host

    assert_difference -> { Table.count } => 1, -> { Game.count } => 1 do
      post waiting_table_start_path(table), as: :json
    end
    assert_response :success
    assert_equal [ "playing", "/tables/#{Table.last.id}" ], response.parsed_body["table"].values_at("status", "path")
  end

  test "the vært changes the rules and makes the table private" do
    table = WaitingTable.set_up(user: @host).table
    sign_in_as @host

    patch waiting_table_settings_path(table), params: { kind: "private", rules: { end_score: "25", queen_breaks_hearts: "0", jack_of_diamonds_minus_ten: "1", shooters_choice: "0" } }

    assert_redirected_to waiting_table_path(table)
    table = table.reload
    assert table.private?
    assert_equal Hjerterfri::Rules.new(end_score: 25, jack_of_diamonds_minus_ten: true), table.rules.game
  end

  test "Opret bord makes a password table, and sitting there takes the password" do
    sign_in_as @host
    post waiting_tables_path, params: { kind: "password", password: "hemmelig" }
    table = @host.current_table
    assert table.password?

    sign_in_as @erik
    get root_path
    assert_select "div#root[data-page=lobby]" do |root|
      assert_equal [ "password" ], JSON.parse(root.first["data-tables"]).map { |entry| entry["kind"] }
    end

    post waiting_table_seat_path(table), params: { position: 1, password: "forkert" }, headers: { "HTTP_REFERER" => root_url }
    assert_redirected_to root_url
    assert_equal "Forkert adgangskode.", flash[:alert]
    assert_not table.reload.seated?(@erik)

    post waiting_table_seat_path(table), params: { position: 1, password: "hemmelig" }
    assert_redirected_to waiting_table_path(table)
    assert table.reload.seated?(@erik)
  end

  test "a password table without a password is refused" do
    sign_in_as @host

    assert_no_difference -> { Table.count } do
      post waiting_tables_path, params: { kind: "password", password: "" }
    end
    assert_equal "Skriv en adgangskode til bordet.", flash[:alert]
  end

  test "a private table is missing from the lobby, but its link opens the waiting room for anyone" do
    sign_in_as @host
    post waiting_tables_path, params: { kind: "private" }
    table = @host.current_table
    assert table.private?

    sign_in_as @erik
    get root_path
    assert_select "div#root[data-page=lobby]" do |root|
      assert_empty JSON.parse(root.first["data-tables"])
    end

    get waiting_table_path(table)
    assert_select "div#root[data-page=waiting]"
    post waiting_table_seat_path(table), params: { position: 3 }
    assert_equal 3, table.reload.seating.seat_of(@erik)
  end
end
