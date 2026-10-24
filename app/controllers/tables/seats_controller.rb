# Sitting down, or moving, in a free seat of a bord that has not started.
# A password table needs its password; a wrong one is refused like any
# other refusal ("Forkert adgangskode").
class Tables::SeatsController < ApplicationController
  include TableRefusals

  def create
    table = Table.find(params[:table_id])
    outcome = TableCommands.new.sit(table:, user: Current.user, seat: Integer(params[:position].to_s, exception: false), password: params[:password])
    return refused(outcome) if outcome.refused?

    redirect_to table_path(table)
  end
end
