# The vært changes the rules and the table type (open, password or
# private) while the table waits for players.
class Tables::SettingsController < ApplicationController
  include RulesParams
  include TableRefusals

  def update
    table = Table.find(params[:table_id])
    rules = chosen_rules
    return redirect_to table_path(table), alert: RulesParams::INVALID_END_SCORE unless rules

    outcome = TableCommands.new.change_settings(table:, user: Current.user, rules:, kind: params[:kind].to_s, password: params[:password])
    return refused(outcome) if outcome.refused?

    redirect_to table_path(table), notice: "Indstillingerne er gemt."
  end
end
