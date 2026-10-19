# The table page. It mounts the React table, which gets its state over
# TableChannel. Only players seated at the table may open it.
class TablesController < ApplicationController
  nav_style :compact

  def show
    @table = Table.find(params[:id])
    raise ActiveRecord::RecordNotFound unless @table.seated?(Current.user)
  end
end
