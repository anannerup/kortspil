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

  test "has a placeholder for active tables" do
    get admin_root_path

    assert_select "h2", "Aktive borde"
  end
end
