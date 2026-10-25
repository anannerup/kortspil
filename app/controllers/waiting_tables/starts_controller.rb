# The vært starts the spil once every seat is taken: only now are the
# table, its seats and the spil stored. Every seated player is sent their
# state; the answer is the stored table, whose page the players go to.
class WaitingTables::StartsController < ApplicationController
  include WaitingTableActions

  def create
    outcome = TableCommands.new.start(table: @table, user: Current.user)
    TableChannel.deliver(outcome) unless outcome.refused?
    answer outcome
  end
end
