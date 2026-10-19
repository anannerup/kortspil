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
end
