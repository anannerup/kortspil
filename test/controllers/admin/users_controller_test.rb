require "test_helper"

class Admin::UsersControllerTest < ActionDispatch::IntegrationTest
  include ActionView::RecordIdentifier

  setup { sign_in_as users(:admin) }

  test "lists every user with their status and actions" do
    get admin_users_path

    assert_response :success
    {
      pending: "Afventer godkendelse", approved: "Godkendt", rejected: "Afvist", blocked: "Blokeret"
    }.each do |fixture, status|
      assert_select "li[id=?]", dom_id(users(fixture)) do
        assert_select ".status", status
      end
    end
    assert_select "li[id=?]", dom_id(users(:approved)) do
      assert_select "form[action=?] button", admin_user_block_path(users(:approved)), text: "Bloker"
      assert_select "a[href=?]", edit_admin_user_password_path(users(:approved))
    end
    assert_select "li[id=?]", dom_id(users(:blocked)) do
      assert_select "form[action=?] button", admin_user_block_path(users(:blocked)), text: "Ophæv blokering"
    end
  end

  test "offers no actions on the admin's own row" do
    get admin_users_path

    assert_select "li[id=?]", dom_id(users(:admin)) do
      assert_select "form", count: 0
      assert_select "a", count: 0
    end
  end

  test "never offers a way to change the admin flag" do
    get admin_users_path

    assert_no_match(/name="user\[admin\]"/, response.body)
  end
end
