# The vært puts a bot in an empty seat, or takes one out, before the start.
class WaitingTables::BotsController < WaitingTables::BaseController
  def create
    render_outcome @table.add_bot(user: Current.user, seat:)
  end

  def destroy
    render_outcome @table.remove_bot(user: Current.user, seat:)
  end
end
