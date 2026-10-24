# A bord's own URL. Before the start it shows the bord waiting for players
# to anyone who may sit there; once a spil is under way it mounts the React
# table, which gets its state over TableChannel, for the seated players
# only. A closed table sends its visitors back to the lobby, as does a
# started one to a player who has forladt its spil (they cannot return).
#
# Creating a table here makes an open table in the lobby, with the user as
# vært.
class TablesController < ApplicationController
  include RulesParams
  include TableRefusals

  nav_style :compact

  def show
    @table = Table.find(params[:id])
    return redirect_to root_path if @table.closed?
    return if @table.seated?(Current.user)
    raise ActiveRecord::RecordNotFound if @table.practice?
    return if @table.waiting?

    forladt = @table.current_game&.forladt_ids&.include?(Current.user.id)
    redirect_to root_path, alert: t(forladt ? "tables.refusals.forladt" : "tables.refusals.not_waiting")
  end

  def create
    rules = chosen_rules
    return redirect_to root_path, alert: RulesParams::INVALID_END_SCORE unless rules

    outcome = TableCommands.new.create_table(user: Current.user, rules:)
    return refused(outcome) if outcome.refused?

    redirect_to table_path(outcome.table)
  end
end
