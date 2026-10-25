# The vært changes the rules and the table type (open, password or
# private) at the bord, before its spil. At a practice bord only the rules.
# The game was chosen in the lobby and is not a setting.
class WaitingTables::SettingsController < ApplicationController
  include RulesParams
  include WaitingTableActions

  def update
    rules = chosen_rules
    return refuse_with(RulesParams::INVALID_END_SCORE, html_to: waiting_table_path(@table)) unless rules

    answer TableCommands.new.change_settings(table: @table, user: Current.user, rules:, kind: params[:kind].to_s, password: params[:password]),
      notice: "Indstillingerne er gemt."
  end
end
