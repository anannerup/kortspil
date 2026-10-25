# The vært kicks a player before the start (WaitingTable#kick).
class WaitingTables::KicksController < WaitingTables::BaseController
  def create
    render_outcome @table.kick(user: Current.user, seat:)
  end
end
