# A stored bord's own URL: its spil, for the seated players only (the React
# table, which gets its state over TableChannel). A closed table sends its
# visitors back to the lobby, as does a started one to a player who has
# forladt its spil (they cannot return) or does not sit there. A bord
# before its spil is a WaitingTable at /borde/:id (WaitingTablesController).
class TablesController < ApplicationController
  nav_style :compact

  def show
    @table = Table.find(params[:id])
    return redirect_to root_path if @table.closed?
    return if @table.seated?(Current.user)
    raise ActiveRecord::RecordNotFound if @table.practice?

    forladt = @table.current_game&.forladt_ids&.include?(Current.user.id)
    redirect_to root_path, alert: t(forladt ? "tables.refusals.forladt" : "tables.refusals.not_waiting")
  end
end
