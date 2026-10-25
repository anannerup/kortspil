# Sitting down, or moving, in a free seat of a bord that has not started.
# A password table needs its password; a wrong one is refused like any
# other refusal ("Forkert adgangskode").
class WaitingTables::SeatsController < ApplicationController
  include WaitingTableActions

  def create
    answer TableCommands.new.sit(table: @table, user: Current.user, seat:, password: params[:password])
  end
end
