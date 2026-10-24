require "test_helper"

class PasswordResetRequestsControllerTest < ActionDispatch::IntegrationTest
  include ActionView::RecordIdentifier

  test "the login page links to the form" do
    get new_session_path

    assert_select "a[href=?]", new_password_reset_request_path
  end

  test "a request by username or email is recorded and answered the same way" do
    user = users(:approved)

    post password_reset_request_path, params: { login: user.email_address.upcase }

    assert_redirected_to new_session_path
    assert user.reload.password_reset_requested_at.present?
  end

  test "an unknown login gets the same answer and records nothing" do
    post password_reset_request_path, params: { login: "nobody-here" }

    assert_redirected_to new_session_path
    assert_equal "Tak. Hvis brugeren findes, får administratoren besked og sætter en ny adgangskode for dig.", flash[:notice]
    assert_equal 0, User.wanting_password_reset.count
  end

  test "the admin sees the request, and setting a new password clears it" do
    user = users(:approved)
    user.request_password_reset!
    sign_in_as users(:admin)

    get admin_root_path
    assert_select "li[id=?]", dom_id(user, :reset)

    patch admin_user_password_path(user), params: { user: { password: "a-new-password", password_confirmation: "a-new-password" } }
    assert_nil user.reload.password_reset_requested_at
    get admin_root_path
    assert_select "li[id=?]", dom_id(user, :reset), count: 0
  end
end
