# The vært starts the spil once every seat is taken: only now is the spil
# created. Every seated player is sent their state; the players' table
# pages reload into the spil.
class Tables::StartsController < ApplicationController
  include TableRefusals

  def create
    table = Table.find(params[:table_id])
    outcome = TableCommands.new.start(table:, user: Current.user)
    TableChannel.deliver(outcome) unless outcome.refused?
    answer outcome
  end
end
