require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  test "an approved user sees the React mount point" do
    sign_in_as users(:approved)

    get root_path

    assert_response :success
    assert_select "div#root"
  end

  test "a visitor is sent to the login page" do
    get root_path

    assert_redirected_to new_session_path
  end
end
