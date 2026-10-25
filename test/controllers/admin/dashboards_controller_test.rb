require "test_helper"

class Admin::DashboardsControllerTest < ActionDispatch::IntegrationTest
  include ActionView::RecordIdentifier

  setup { sign_in_as users(:admin) }

  test "lists pending users with approve and reject" do
    get admin_root_path

    assert_response :success
    assert_select "li[id=?]", dom_id(users(:pending)) do
      assert_select "form[action=?] button", admin_user_approval_path(users(:pending)), text: "Godkend"
      assert_select "form[action=?] button", admin_user_rejection_path(users(:pending)), text: "Afvis"
    end
    assert_select "li[id=?]", dom_id(users(:approved)), count: 0
  end

  test "lists the active tables, not the closed ones" do
    open_table = TableCommands.new.create_table(user: users(:erik)).table
    practice = started_practice(users(:frida))
    closed = TableCommands.new.create_table(user: users(:approved)).table
    TableCommands.new.leave(table: closed, user: users(:approved))

    get admin_root_path

    assert_select "h2", "Aktive borde"
    assert_select "li[id=?]", dom_id(open_table) do
      assert_select ".pill", "Åbent"
      assert_select ".host", "Erik"
      assert_select ".pill", "Venter på spillere"
    end
    assert_select "li[id=?]", dom_id(practice) do
      assert_select ".pill", "Øvebord"
      assert_select ".players", "Frida, Bot 1, Bot 2, Bot 3"
      assert_select ".pill", "I gang"
    end
    assert_select "li[id=?]", dom_id(closed), count: 0
  end
end
