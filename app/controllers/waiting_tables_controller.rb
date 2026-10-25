# A bord before its spil, at /borde/:id. It lives in memory (WaitingTable)
# until the vært starts the spil. The page (TableSetup) shows the bord to
# anyone with the link (a practice bord only to its player) and follows it
# live on LobbyChannel. Once the bord has started, the link leads to the
# stored table; a bord that is gone (closed, or dropped by a restart) sends
# the visitor back to the lobby.
#
# Creating one is "Hjerterfri" in the lobby: a bord for that game, of the
# type the user chose (open by default), with the user as vært.
class WaitingTablesController < ApplicationController
  nav_style :compact

  def show
    @table = WaitingTables.default.find(params[:id])
    return gone unless @table
    raise ActiveRecord::RecordNotFound if @table.practice? && !@table.seated?(Current.user)

    @friends = Current.user.friends.alphabetically.map { |friend| { id: friend.id, username: friend.username, online: friend.online? } }
  end

  def create
    outcome = WaitingTable.set_up(user: Current.user, rules: rules_form, game: params[:game].presence || "hjerterfri",
      kind: params[:kind].presence || "open", password: params[:password])
    return render_refusal(outcome) if outcome.refused?

    redirect_to waiting_table_path(outcome.table)
  end

  private

  def rules_form = params.fetch(:rules, {}).permit(*GameRules.form_fields)

  def gone
    started = WaitingTables.default.started_as(params[:id])
    return redirect_to table_path(started) if started

    redirect_to root_path, alert: t("tables.refusals.gone")
  end
end
