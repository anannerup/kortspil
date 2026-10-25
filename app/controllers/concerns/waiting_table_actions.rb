# For the actions on a bord before its spil (/borde/:waiting_table_id/...):
# finds the bord in memory (WaitingTables), or refuses like any table
# command when it has started (:not_waiting) or is gone (:gone, e.g. after
# a restart).
module WaitingTableActions
  extend ActiveSupport::Concern
  include TableRefusals

  included do
    before_action :set_waiting_table
  end

  private

  def set_waiting_table
    @table = WaitingTables.default.find(params[:waiting_table_id])
    return if @table

    refuse_with(t(WaitingTables.default.started_as(params[:waiting_table_id]) ? "tables.refusals.not_waiting" : "tables.refusals.gone"))
  end

  def seat = Integer(params[:position].to_s, exception: false)
end
