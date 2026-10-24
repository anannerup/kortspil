# The admin front page: users awaiting approval and the active tables.
class Admin::DashboardsController < Admin::BaseController
  def show
    @pending_users = User.pending.order(:created_at)
    @active_tables = Table.active.includes(:host)
  end
end
