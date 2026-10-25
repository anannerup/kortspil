# The vært changes the rules and the table type (open, password or
# private) at the table, while it waits for players. At a practice table
# only the rules.
class Tables::SettingsController < ApplicationController
  include RulesParams
  include TableRefusals

  def update
    table = Table.find(params[:table_id])
    rules = chosen_rules
    return refuse_with(RulesParams::INVALID_END_SCORE, html_to: table_path(table)) unless rules

    answer TableCommands.new.change_settings(table:, user: Current.user, rules:, kind: params[:kind].to_s, password: params[:password]), notice: "Indstillingerne er gemt."
  end
end
