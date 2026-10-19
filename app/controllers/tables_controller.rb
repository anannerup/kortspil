# The table page. It mounts the React table, which gets its state over
# TableChannel. Only players seated at the table may open it, and only
# while it is open; a closed table sends them back to the lobby.
class TablesController < ApplicationController
  nav_style :compact

  def show
    @table = Table.find(params[:id])
    raise ActiveRecord::RecordNotFound unless @table.seated?(Current.user)

    redirect_to root_path if @table.closed?
  end
end
