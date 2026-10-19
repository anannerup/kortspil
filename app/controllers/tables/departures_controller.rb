# "Forlad bordet": the player leaves the table and goes back to the lobby.
# Leaving a spil in progress forfeits it (see TableCommands#leave).
class Tables::DeparturesController < ApplicationController
  def create
    table = Table.find(params[:table_id])
    TableChannel.deliver(TableCommands.new.leave(table:, user: Current.user))
    redirect_to root_path
  end
end
