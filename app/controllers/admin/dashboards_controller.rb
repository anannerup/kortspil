# The admin front page: users awaiting approval, users who forgot their
# password, and the active tables: those waiting for their spil (in
# memory) and those playing.
class Admin::DashboardsController < Admin::BaseController
  def show
    @pending_users = User.pending.order(:created_at)
    @reset_requests = User.wanting_password_reset
    @active_tables = WaitingTables.default.all + Table.active.includes(:host)
  end
end
