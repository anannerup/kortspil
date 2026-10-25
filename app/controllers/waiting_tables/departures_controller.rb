# The player stands up from a bord before its spil and goes back to the
# lobby (WaitingTable#leave). The last human closes it.
class WaitingTables::DeparturesController < WaitingTables::BaseController
  def create
    @table.leave(user: Current.user)
    redirect_to root_path
  end
end
