# The player stands up from a bord before its spil and goes back to the
# lobby. The last human closes it.
class WaitingTables::DeparturesController < ApplicationController
  include WaitingTableActions

  def create
    TableCommands.new.leave(table: @table, user: Current.user)
    redirect_to root_path
  end
end
