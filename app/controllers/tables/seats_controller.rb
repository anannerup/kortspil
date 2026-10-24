# Sitting down, or moving, in a free seat of a bord that has not started.
class Tables::SeatsController < ApplicationController
  include TableRefusals

  def create
    table = Table.find(params[:table_id])
    outcome = TableCommands.new.sit(table:, user: Current.user, seat: Integer(params[:position].to_s, exception: false))
    return refused(outcome) if outcome.refused?

    redirect_to table_path(table)
  end
end
