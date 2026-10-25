require "test_helper"

class TablesControllerTest < ActionDispatch::IntegrationTest
  test "Øvebord creates a practice table that waits at the table, with no spil yet" do
    sign_in_as users(:approved)

    assert_difference -> { Table.count } => 1, -> { Game.count } => 0 do
      post practice_tables_path
    end

    table = Table.last
    assert table.waiting?
    assert_redirected_to table_path(table)
    follow_redirect!
    assert_response :success
    assert_select "div#root[data-page=waiting]"
    entry = JSON.parse(css_select("div#root").first["data-table"])
    assert_equal [ "practice", [ users(:approved).username, "Bot 1", "Bot 2", "Bot 3" ] ], [ entry["kind"], entry["seats"].map { |seat| seat["name"] } ]
  end

  test "Øvebord takes the rules chosen, and the spil starts with them from the table" do
    user = users(:approved)
    sign_in_as user

    post practice_tables_path, params: { rules: { end_score: "50", queen_breaks_hearts: "0", jack_of_diamonds_minus_ten: "1", shooters_choice: "1" } }
    table = Table.last
    expected = Hjerterfri::Rules.new(end_score: 50, jack_of_diamonds_minus_ten: true, shooters_choice: true)
    assert_equal expected, table.engine_rules

    assert_difference -> { Game.count } => 1, -> { Round.count } => 1 do
      post table_start_path(table)
    end
    assert_redirected_to table_path(table)
    follow_redirect!
    assert_select "div#root[data-page=table][data-table-id=?]", table.id.to_s
    assert_equal expected, table.current_game.engine_rules
  end

  test "the practice player changes the rules at the table before starting" do
    user = users(:approved)
    table = TableCommands.new.start_practice(user:).table
    sign_in_as user

    patch table_settings_path(table), params: { rules: { end_score: "40", queen_breaks_hearts: "1", jack_of_diamonds_minus_ten: "0", shooters_choice: "0" } }, as: :json

    assert_response :success
    assert_equal 40, response.parsed_body.dig("table", "rules", "end_score")
    assert table.reload.practice?
  end

  test "Øvebord refuses an end score that is not a positive whole number" do
    sign_in_as users(:approved)

    [ "0", "-5", "abc", "7.5", "" ].each do |end_score|
      assert_no_difference -> { Table.count } do
        post practice_tables_path, params: { rules: { end_score: } }
      end
      assert_redirected_to root_path
      assert_equal "Slutpoint skal være et helt tal over 0.", flash[:alert]
    end
  end

  test "the lobby gives the form the standard preset" do
    sign_in_as users(:approved)

    get root_path

    assert_select "div#root[data-page=lobby][data-standard-rules=?]", Hjerterfri::Rules.standard.to_h.to_json
  end

  test "a user who does not sit at the table cannot open it" do
    table = started_practice(users(:approved))
    sign_in_as users(:admin)

    get table_path(table)

    assert_response :not_found
  end

  test "a pending user cannot start a practice table" do
    sign_in_as users(:pending)

    assert_no_difference -> { Table.count } do
      post practice_tables_path
    end
    assert_redirected_to approval_path
  end

  test "Forlad bordet forfeits the spil, closes the table and goes back to the lobby" do
    user = users(:approved)
    table = started_practice(user)
    sign_in_as user

    post table_departure_path(table)

    assert_redirected_to root_path
    assert table.reload.closed?
    assert table.current_game.abandoned?
    assert_equal user, table.current_game.forfeited_by
  end

  test "a closed table sends its player back to the lobby" do
    user = users(:approved)
    table = started_practice(user)
    TableCommands.new.leave(table:, user:)
    sign_in_as user

    get table_path(table)

    assert_redirected_to root_path
  end

  test "a user who does not sit at the table cannot leave it for its player" do
    table = started_practice(users(:approved))
    sign_in_as users(:admin)

    post table_departure_path(table)

    assert_redirected_to root_path
    assert table.reload.playing?
  end
end
