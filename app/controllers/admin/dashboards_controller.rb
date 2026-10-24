# The admin front page: users awaiting approval, users who forgot their
# password, and the active tables.
class Admin::DashboardsController < Admin::BaseController
  def show
    @pending_users = User.pending.order(:created_at)
    @reset_requests = User.wanting_password_reset
    @active_tables = Table.active.includes(:host)
  end
end
