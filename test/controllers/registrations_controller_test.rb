require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  test "shows the signup form" do
    get new_registration_path

    assert_response :success
    assert_select "input[name='user[username]']"
  end

  test "signs up, logs in and lands on the waiting page" do
    assert_difference -> { User.count } do
      post registration_path, params: { user: {
        username: "Ellen", email_address: "Ellen@Example.com",
        password: "hemmelig1", password_confirmation: "hemmelig1"
      } }
    end

    user = User.find_by!(username: "Ellen")
    assert_equal "ellen@example.com", user.email_address
    assert user.pending?
    assert cookies[:session_id].present?

    follow_redirect!
    assert_redirected_to approval_path
    follow_redirect!
    assert_select "h1", "Afventer godkendelse"
  end

  test "admin flag and approval state cannot be set at signup" do
    post registration_path, params: { user: {
      username: "Snyder", email_address: "snyder@example.com",
      password: "hemmelig1", password_confirmation: "hemmelig1",
      admin: true, approval_state: "approved"
    } }

    user = User.find_by!(username: "Snyder")
    assert_not user.admin?
    assert user.pending?
  end

  test "re-renders the form with Danish errors when invalid" do
    assert_no_difference -> { User.count } do
      post registration_path, params: { user: {
        username: "ANNA", email_address: "ny@example.com",
        password: "hemmelig1", password_confirmation: "hemmelig1"
      } }
    end

    assert_response :unprocessable_entity
    assert_select ".errors li", "Brugernavn er allerede i brug"
    assert_nil cookies[:session_id]
  end

  test "a signed-in user is sent away from the signup form" do
    sign_in_as users(:approved)

    get new_registration_path

    assert_redirected_to root_path
  end
end
