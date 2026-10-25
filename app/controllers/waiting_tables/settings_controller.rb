# The vært changes the bord's rules (the table type: open, password or
# private; at es-makker the number of runder; and the card game's rules)
# at the bord, before its spil. At a practice bord only the game's rules.
# The game was chosen in the lobby and is not a setting.
class WaitingTables::SettingsController < WaitingTables::BaseController
  def update
    outcome = @table.change_settings(user: Current.user, rules: rules_form, kind: params[:kind].to_s, password: params[:password], runder: params[:runder])
    render_outcome outcome, notice: "Indstillingerne er gemt.", refused_to: waiting_table_path(@table)
  end

  private

  def rules_form = params.fetch(:rules, {}).permit(*GameRules.form_fields(@table.game))
end
