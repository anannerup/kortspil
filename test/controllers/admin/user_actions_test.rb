require "test_helper"

class Admin::UserActionsTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:admin)
    sign_in_as @admin
  end

  test "approves a pending user" do
    post admin_user_approval_path(users(:pending))

    assert_redirected_to admin_users_path
    assert users(:pending).reload.approved?
  end

  test "approves a rejected user" do
    post admin_user_approval_path(users(:rejected))

    assert users(:rejected).reload.approved?
  end

  test "rejects a pending user" do
    post admin_user_rejection_path(users(:pending))

    assert_redirected_to admin_users_path
    assert users(:pending).reload.rejected?
  end

  test "unapproves an approved user" do
    delete admin_user_approval_path(users(:approved))

    assert_redirected_to admin_users_path
    assert users(:approved).reload.pending?
  end

  test "goes back to the page the admin came from" do
    post admin_user_approval_path(users(:pending)), headers: { "HTTP_REFERER" => admin_root_url }

    assert_redirected_to admin_root_url
  end

  test "blocks a user and ends their sessions" do
    user = users(:approved)
    user.sessions.create!
    user.sessions.create!

    assert_difference -> { user.sessions.count }, -2 do
      post admin_user_block_path(user)
    end

    assert_redirected_to admin_users_path
    assert user.reload.blocked?
  end

  test "a blocked user's open session no longer works" do
    user = users(:approved)
    sign_in_as user
    session_cookie = cookies["session_id"]
    sign_in_as @admin

    post admin_user_block_path(user)

    cookies["session_id"] = session_cookie
    get root_path
    assert_redirected_to new_session_path
  end

  test "unblocks a blocked user" do
    delete admin_user_block_path(users(:blocked))

    assert_redirected_to admin_users_path
    assert users(:blocked).reload.approved?
  end

  test "sets a new password and ends the user's sessions" do
    user = users(:approved)
    user.sessions.create!

    get edit_admin_user_password_path(user)
    assert_response :success

    patch admin_user_password_path(user), params: { user: { password: "nyhemmelig", password_confirmation: "nyhemmelig" } }

    assert_redirected_to admin_users_path
    assert user.reload.authenticate("nyhemmelig")
    assert_empty user.sessions
  end

  test "refuses a too short or mismatched new password" do
    user = users(:approved)

    patch admin_user_password_path(user), params: { user: { password: "kort", password_confirmation: "kort" } }
    assert_response :unprocessable_entity

    patch admin_user_password_path(user), params: { user: { password: "nyhemmelig", password_confirmation: "andet123" } }
    assert_response :unprocessable_entity

    assert user.reload.authenticate("password")
  end

  test "refuses a blank new password" do
    patch admin_user_password_path(users(:approved)), params: { user: { password: "", password_confirmation: "" } }

    assert_response :unprocessable_entity
    assert users(:approved).reload.authenticate("password")
  end

  test "the admin cannot block, unapprove, reject or reset themselves" do
    post admin_user_block_path(@admin)
    delete admin_user_approval_path(@admin)
    post admin_user_rejection_path(@admin)
    patch admin_user_password_path(@admin), params: { user: { password: "nyhemmelig", password_confirmation: "nyhemmelig" } }

    assert_redirected_to admin_users_path
    assert_equal "Du kan ikke ændre din egen konto her.", flash[:alert]
    @admin.reload
    assert @admin.approved?
    assert @admin.admin?
    assert @admin.authenticate("password")
    assert_not_empty @admin.sessions
  end

  test "an unknown user is a 404" do
    post admin_user_block_path(user_id: 0)

    assert_response :not_found
  end
end
