# "Start spil": the vært starts the spil once every seat is taken; only now
# are the table, its seats and the spil stored (WaitingTable#start). Every
# seated player is sent their state; the answer is the stored table, whose
# page the players go to.
class WaitingTables::StartsController < WaitingTables::BaseController
  def create
    outcome = @table.start(user: Current.user)
    TableChannel.deliver(outcome) if outcome.accepted?
    render_outcome outcome
  end
end
