# "Øvebord": a table with the user and three bots, with the rules the user
# chose (the "Standard hjerterfri" preset when none are sent). Like any
# bord it waits in memory until its spil starts: the user can change the
# rules at the table and starts the spil there.
class PracticeTablesController < ApplicationController
  include RulesParams
  include TableRefusals

  def create
    rules = chosen_rules
    return redirect_to root_path, alert: RulesParams::INVALID_END_SCORE unless rules

    outcome = TableCommands.new.start_practice(user: Current.user, rules:)
    return refused(outcome) if outcome.refused?

    redirect_to waiting_table_path(outcome.table)
  end
end
