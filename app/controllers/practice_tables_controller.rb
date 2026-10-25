# "Øvebord": a table with the user and three bots, with the rules the user
# chose (the "Standard hjerterfri" preset when none are sent). Like any
# bord it waits in memory until its spil starts: the user can change the
# rules at the table and starts the spil there.
class PracticeTablesController < ApplicationController
  def create
    outcome = WaitingTable.set_up_practice(user: Current.user, rules: rules_form)
    return render_refusal(outcome) if outcome.refused?

    redirect_to waiting_table_path(outcome.table)
  end

  private

  def rules_form = params.fetch(:rules, {}).permit(*GameRules.form_fields)
end
