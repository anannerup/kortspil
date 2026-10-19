require "test_helper"

class ApprovalsControllerTest < ActionDispatch::IntegrationTest
  test "a pending user is redirected from every page to the waiting page" do
    sign_in_as users(:pending)

    [ root_path, edit_password_path ].each do |path|
      get path
      assert_redirected_to approval_path
    end

    get approval_path
    assert_response :success
    assert_select "h1", "Afventer godkendelse"
    assert_select "form[action='#{session_path}'] button", "Log ud"
  end

  test "a rejected user only sees the waiting page" do
    sign_in_as users(:rejected)

    get root_path
    assert_redirected_to approval_path

    get approval_path
    assert_response :success
  end

  test "access opens once the user is approved" do
    user = users(:pending)
    sign_in_as user
    user.approved!

    get root_path

    assert_response :success
    assert_select "div#root"
  end

  test "an approved user is sent from the waiting page to the lobby" do
    sign_in_as users(:approved)

    get approval_path

    assert_redirected_to root_path
  end

  test "a visitor must log in first" do
    get approval_path

    assert_redirected_to new_session_path
  end
end
