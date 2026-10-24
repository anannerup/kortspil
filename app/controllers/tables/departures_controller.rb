# "Forlad bordet": the player leaves the table and goes back to the lobby.
# Before the start or after the end that is standing up; leaving a spil in
# progress forlader it: a bot takes the seat and the player has lost it
# (see TableCommands#leave).
class Tables::DeparturesController < ApplicationController
  def create
    table = Table.find(params[:table_id])
    TableChannel.deliver(TableCommands.new.leave(table:, user: Current.user))
    redirect_to root_path
  end
end
