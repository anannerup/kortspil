# The table page. It mounts the React table, which gets its state over
# TableChannel. Only players seated at the table may open it, and only
# while it is open; a closed table sends them back to the lobby.
class TablesController < ApplicationController
  def show
    @table = Table.find(params[:id])
    return head :not_found unless @table.seated?(Current.user)

    redirect_to root_path if @table.closed?
  end
end
