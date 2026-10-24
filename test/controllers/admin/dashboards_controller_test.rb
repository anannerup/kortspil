require "test_helper"

class Admin::DashboardsControllerTest < ActionDispatch::IntegrationTest
  include ActionView::RecordIdentifier

  setup { sign_in_as users(:admin) }

  test "lists pending users with approve and reject" do
    get admin_root_path

    assert_response :success
    assert_select "tr[id=?]", dom_id(users(:pending)) do
      assert_select "form[action=?] button", admin_user_approval_path(users(:pending)), text: "Godkend"
      assert_select "form[action=?] button", admin_user_rejection_path(users(:pending)), text: "Afvis"
    end
    assert_select "tr[id=?]", dom_id(users(:approved)), count: 0
  end

  test "lists the active tables, not the closed ones" do
    open_table = TableCommands.new.create_table(user: users(:erik)).table
    practice = TableCommands.new.start_practice(user: users(:frida)).table
    closed = TableCommands.new.create_table(user: users(:approved)).table
    TableCommands.new.leave(table: closed, user: users(:approved))

    get admin_root_path

    assert_select "h2", "Aktive borde"
    assert_select "tr[id=?]", dom_id(open_table) do
      assert_select "td", "Åbent"
      assert_select "td", "Erik"
      assert_select "td", "Venter på spillere"
    end
    assert_select "tr[id=?]", dom_id(practice) do
      assert_select "td", "Øvebord"
      assert_select "td", "Frida, Bot 1, Bot 2, Bot 3"
      assert_select "td", "I gang"
    end
    assert_select "tr[id=?]", dom_id(closed), count: 0
  end
end
