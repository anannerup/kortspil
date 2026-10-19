require "test_helper"

class UserTest < ActiveSupport::TestCase
  def build_user(**attributes)
    User.new(username: "Ellen", email_address: "ellen@example.com", password: "hemmelig1", **attributes)
  end

  test "downcases and strips email_address" do
    user = User.new(email_address: " DOWNCASED@EXAMPLE.COM ")
    assert_equal("downcased@example.com", user.email_address)
  end

  test "strips username but keeps its case" do
    assert_equal "Ellen", User.new(username: " Ellen ").username
  end

  test "new users are pending and not admin" do
    user = build_user

    assert user.pending?
    assert_not user.admin?
  end

  test "username is unique regardless of case" do
    user = build_user(username: "anna")

    assert_not user.valid?
    assert user.errors.of_kind?(:username, :taken)
  end

  test "username must be 3 to 20 letters, digits, - or _" do
    %w[ab æble anna@x has\ space #{"a" * 21}].each do |username|
      assert_not build_user(username: username).valid?, "#{username.inspect} should be invalid"
    end
    %w[abc Ole-Bole ny_spiller 2tal].each do |username|
      assert build_user(username: username).valid?, "#{username.inspect} should be valid"
    end
  end

  test "email address is unique and must look like an email" do
    assert_not build_user(email_address: "ANNA@example.com").valid?
    assert_not build_user(email_address: "not-an-email").valid?
  end

  test "password must be at least 8 characters" do
    assert_not build_user(password: "short").valid?
  end

  test "authenticate_by_login accepts username or email" do
    assert_equal users(:approved), User.authenticate_by_login("ANNA", "password")
    assert_equal users(:approved), User.authenticate_by_login("anna@example.com", "password")
    assert_nil User.authenticate_by_login("Anna", "wrong")
    assert_nil User.authenticate_by_login("nobody", "password")
    assert_nil User.authenticate_by_login("", "password")
  end
end
