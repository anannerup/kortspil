# A bord's own URL. Before the start it shows the bord waiting for players
# to anyone who may sit there; once a spil is under way it mounts the React
# table, which gets its state over TableChannel, for the seated players
# only. A closed table sends its visitors back to the lobby.
#
# Creating a table here makes a table of the type the user chose (open,
# password or private), with the user as vært.
class TablesController < ApplicationController
  include RulesParams
  include TableRefusals

  nav_style :compact

  def show
    @table = Table.find(params[:id])
    return redirect_to root_path if @table.closed?
    return if @table.seated?(Current.user)
    raise ActiveRecord::RecordNotFound if @table.practice?

    redirect_to root_path, alert: t("tables.refusals.not_waiting") unless @table.waiting?
  end

  def create
    rules = chosen_rules
    return redirect_to root_path, alert: RulesParams::INVALID_END_SCORE unless rules

    outcome = TableCommands.new.create_table(user: Current.user, rules:, kind: params[:kind].presence || "open", password: params[:password])
    return refused(outcome) if outcome.refused?

    redirect_to table_path(outcome.table)
  end
end
