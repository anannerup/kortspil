require "test_helper"

class TablesControllerTest < ActionDispatch::IntegrationTest
  test "Øvebord creates a practice table and opens it" do
    sign_in_as users(:approved)

    assert_difference -> { Table.count } => 1, -> { Game.count } => 1, -> { Round.count } => 1 do
      post practice_tables_path
    end

    table = Table.last
    assert_redirected_to table_path(table)
    follow_redirect!
    assert_response :success
    assert_select "div#root[data-page=table][data-table-id=?]", table.id.to_s
  end

  test "Øvebord starts with the rules chosen in the lobby" do
    sign_in_as users(:approved)

    post practice_tables_path, params: { rules: { end_score: "50", queen_breaks_hearts: "0", jack_of_diamonds_minus_ten: "1", shooters_choice: "1" } }

    expected = Hjerterfri::Rules.new(end_score: 50, jack_of_diamonds_minus_ten: true, shooters_choice: true)
    assert_equal expected, Table.last.engine_rules
    assert_equal expected, Table.last.current_game.engine_rules
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
    table = TableCommands.new.start_practice(user: users(:approved)).table
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
    table = TableCommands.new.start_practice(user:).table
    sign_in_as user

    post table_departure_path(table)

    assert_redirected_to root_path
    assert table.reload.closed?
    assert table.current_game.abandoned?
    assert_equal user, table.current_game.forfeited_by
  end

  test "a closed table sends its player back to the lobby" do
    user = users(:approved)
    table = TableCommands.new.start_practice(user:).table
    TableCommands.new.leave(table:, user:)
    sign_in_as user

    get table_path(table)

    assert_redirected_to root_path
  end

  test "a user who does not sit at the table cannot leave it for its player" do
    table = TableCommands.new.start_practice(user: users(:approved)).table
    sign_in_as users(:admin)

    post table_departure_path(table)

    assert_redirected_to root_path
    assert table.reload.playing?
  end
end
