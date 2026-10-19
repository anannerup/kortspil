require "test_helper"
require "rake"

class UsersRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks if Rake::Task.tasks.none?
    @task = Rake::Task["users:create_admin"]
    @task.reenable
  end

  test "creates an approved admin" do
    capture_io { @task.invoke("anders", "anders@example.com", "anders123") }

    user = User.find_by_login("anders")
    assert user.admin?
    assert user.approved?
    assert user.authenticate("anders123")
  end

  test "promotes an existing user without changing their password" do
    user = User.create!(username: "signe", email_address: "signe@example.com", password: "hemmelig1")

    capture_io { @task.invoke("signe") }

    user.reload
    assert user.admin?
    assert user.approved?
    assert user.authenticate("hemmelig1")
  end
end
