# "Øvebord": a table with the user and three bots that starts at once, with
# the rules the user chose in the lobby (the "Standard hjerterfri" preset
# when none are sent).
class PracticeTablesController < ApplicationController
  include RulesParams
  include TableRefusals

  def create
    rules = chosen_rules
    return redirect_to root_path, alert: RulesParams::INVALID_END_SCORE unless rules

    outcome = TableCommands.new.start_practice(user: Current.user, rules:)
    return refused(outcome) if outcome.refused?

    TableChannel.deliver(outcome)
    redirect_to table_path(outcome.table)
  end
end
