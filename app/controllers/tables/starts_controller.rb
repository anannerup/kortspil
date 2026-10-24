# The vært starts the spil once every seat is taken. Every seated player is
# sent their state; the waiting players' pages reload into the table.
class Tables::StartsController < ApplicationController
  include TableRefusals

  def create
    table = Table.find(params[:table_id])
    outcome = TableCommands.new.start(table:, user: Current.user)
    return refused(outcome) if outcome.refused?

    TableChannel.deliver(outcome)
    redirect_to table_path(table)
  end
end
