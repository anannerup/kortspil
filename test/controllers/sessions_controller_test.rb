require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  test "shows the login form" do
    get new_session_path

    assert_response :success
    assert_select "input[name=login]"
  end

  test "logs in by username, ignoring case" do
    post session_path, params: { login: "anna", password: "password" }

    assert_redirected_to root_path
    assert cookies[:session_id].present?
    follow_redirect!
    assert_response :success
    assert_select "div#root"
  end

  test "logs in by email address, ignoring case" do
    post session_path, params: { login: " Anna@Example.com ", password: "password" }

    assert_redirected_to root_path
    assert cookies[:session_id].present?
  end

  test "refuses a wrong password" do
    post session_path, params: { login: "Anna", password: "wrong" }

    assert_redirected_to new_session_path
    assert_nil cookies[:session_id]
    follow_redirect!
    assert_select ".flash-alert", "Forkert brugernavn, e-mail eller adgangskode."
  end

  test "refuses an unknown login" do
    post session_path, params: { login: "nobody", password: "password" }

    assert_redirected_to new_session_path
    assert_nil cookies[:session_id]
  end

  test "refuses a blocked user with a plain message" do
    post session_path, params: { login: "Dorte", password: "password" }

    assert_redirected_to new_session_path
    assert_nil cookies[:session_id]
    follow_redirect!
    assert_select ".flash-alert", "Din konto er blokeret. Du kan ikke logge ind."
  end

  test "a blocked user with an existing session is logged out" do
    user = users(:approved)
    sign_in_as user
    user.blocked!

    get root_path

    assert_redirected_to new_session_path
    assert_equal 0, user.sessions.count
  end

  test "logs out" do
    sign_in_as users(:approved)

    delete session_path

    assert_redirected_to new_session_path
    assert_empty cookies[:session_id]
  end

  test "a pending user can log out" do
    sign_in_as users(:pending)

    delete session_path

    assert_redirected_to new_session_path
    assert_empty cookies[:session_id]
  end
end
