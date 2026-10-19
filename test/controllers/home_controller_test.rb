require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  test "root renders the React mount point" do
    get root_path

    assert_response :success
    assert_select "div#root"
  end
end
