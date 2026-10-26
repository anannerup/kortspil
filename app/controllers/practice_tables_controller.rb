# "Øvebord": a table with the user and three bots, for the game they chose
# (hjerterfri unless they chose es-makker), with the rules the user chose
# (the game's standard rules when none are sent). Like any bord it waits in
# memory until its spil starts: the user can change the rules at the table
# and starts the spil there.
class PracticeTablesController < ApplicationController
  def create
    outcome = WaitingTable.set_up_practice(user: Current.user, rules: rules_form, game:)
    return render_refusal(outcome) if outcome.refused?

    redirect_to waiting_table_path(outcome.table)
  end

  private

  def game = params[:game].presence || "hjerterfri"

  # An unknown game has no rules form; the bord refuses it.
  def rules_form = GameRules::GAMES.include?(game) ? params.fetch(:rules, {}).permit(*GameRules.form_fields(game)) : {}
end
