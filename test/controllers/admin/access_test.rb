require "test_helper"

class Admin::AccessTest < ActionDispatch::IntegrationTest
  ADMIN_REQUESTS = [
    [ :get, -> { admin_root_path } ],
    [ :get, -> { admin_users_path } ],
    [ :post, -> { admin_user_approval_path(users(:pending)) } ],
    [ :delete, -> { admin_user_approval_path(users(:approved)) } ],
    [ :post, -> { admin_user_rejection_path(users(:pending)) } ],
    [ :post, -> { admin_user_block_path(users(:approved)) } ],
    [ :delete, -> { admin_user_block_path(users(:blocked)) } ],
    [ :get, -> { edit_admin_user_password_path(users(:approved)) } ],
    [ :patch, -> { admin_user_password_path(users(:approved)) } ]
  ].freeze

  test "non-admins get 404 on every admin route and change nothing" do
    sign_in_as users(:approved)

    ADMIN_REQUESTS.each do |verb, path|
      send verb, instance_exec(&path), params: { user: { password: "nyhemmelig", password_confirmation: "nyhemmelig" } }
      assert_response :not_found, "#{verb} #{instance_exec(&path)}"
    end
    assert users(:pending).reload.pending?
    assert users(:approved).reload.approved?
    assert users(:blocked).reload.blocked?
    assert users(:approved).authenticate("password")
  end

  test "logged-out visitors are sent to login on every admin route" do
    ADMIN_REQUESTS.each do |verb, path|
      send verb, instance_exec(&path)
      assert_redirected_to new_session_path, "#{verb} #{instance_exec(&path)}"
    end
    assert users(:pending).reload.pending?
  end

  test "admins see the Admin link in the Konto sub-navigation, others don't" do
    sign_in_as users(:approved)
    get edit_password_path
    assert_select "nav.konto-nav a", text: "Admin", count: 0

    sign_in_as users(:admin)
    get edit_password_path
    assert_select "nav.konto-nav a[href=?]", admin_root_path, text: "Admin"
  end
end
