# The admin front page: users awaiting approval and (later) active tables.
class Admin::DashboardsController < Admin::BaseController
  def show
    @pending_users = User.pending.order(:created_at)
  end
end
