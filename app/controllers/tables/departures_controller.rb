# "Forlad bordet": the player leaves the stored table and goes back to the
# lobby. After the end that is standing up; leaving a spil in progress
# forlader it: a bot takes the seat and the player has lost it (see
# Table::Leaving). Standing up before the start is
# WaitingTables::DeparturesController.
class Tables::DeparturesController < ApplicationController
  def create
    table = Table.find(params[:table_id])
    TableChannel.deliver(table.leave(user: Current.user))
    redirect_to root_path
  end
end
