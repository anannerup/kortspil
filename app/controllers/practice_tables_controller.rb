# "Øvebord": a table with the user and three bots that starts at once, with
# the rules the user chose in the lobby (the "Standard hjerterfri" preset
# when none are sent).
class PracticeTablesController < ApplicationController
  def create
    rules = chosen_rules
    return redirect_to root_path, alert: "Slutpoint skal være et helt tal over 0." unless rules

    outcome = TableCommands.new.start_practice(user: Current.user, rules:)
    TableChannel.deliver(outcome)
    redirect_to table_path(outcome.table)
  end

  private

  # The rules from the form, or nil when the end score is not a positive
  # whole number. Unticked toggles are off.
  def chosen_rules
    form = params.fetch(:rules, {}).permit(:end_score, *Hjerterfri::Rules::TOGGLES)
    return Hjerterfri::Rules.standard if form.empty?

    end_score = Integer(form[:end_score], exception: false)
    return nil unless end_score&.positive?

    toggles = Hjerterfri::Rules::TOGGLES.index_with { |toggle| form[toggle] == "1" }
    Hjerterfri::Rules.new(end_score:, **toggles)
  end
end
