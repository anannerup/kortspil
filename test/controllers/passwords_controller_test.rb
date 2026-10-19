require "test_helper"

class PasswordsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:approved)
    sign_in_as @user
  end

  test "shows the change password form" do
    get edit_password_path

    assert_response :success
    assert_select "input[name='user[password_challenge]']"
  end

  test "changes the password with the right current password" do
    patch password_path, params: { user: {
      password_challenge: "password", password: "nyhemmelig", password_confirmation: "nyhemmelig"
    } }

    assert_redirected_to root_path
    assert @user.reload.authenticate("nyhemmelig")
  end

  test "rejects a wrong current password" do
    patch password_path, params: { user: {
      password_challenge: "wrong", password: "nyhemmelig", password_confirmation: "nyhemmelig"
    } }

    assert_response :unprocessable_entity
    assert_select ".errors li", "Nuværende adgangskode er ugyldig"
    assert @user.reload.authenticate("password")
  end

  test "rejects a blank new password" do
    patch password_path, params: { user: {
      password_challenge: "password", password: "", password_confirmation: ""
    } }

    assert_response :unprocessable_entity
    assert @user.reload.authenticate("password")
  end

  test "requires login" do
    sign_out

    get edit_password_path

    assert_redirected_to new_session_path
  end
end
