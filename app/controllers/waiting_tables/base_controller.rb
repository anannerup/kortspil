# For the actions on a bord before its spil (/borde/:waiting_table_id/...):
# finds the bord in memory (WaitingTables), whose action the controller
# runs and renders (#render_outcome). A bord that has started or is gone
# (e.g. after a restart) is refused as the registry says.
class WaitingTables::BaseController < ApplicationController
  before_action :set_table

  private

  def set_table
    @table = WaitingTables.default.find(params[:waiting_table_id])
    render_refusal(Table::Outcome.new(table: nil, refusal: WaitingTables.default.missing_refusal(params[:waiting_table_id]))) unless @table
  end

  def seat = Integer(params[:position].to_s, exception: false)
end
