# "Øvebord": a table with the user and three bots that starts at once.
class PracticeTablesController < ApplicationController
  def create
    outcome = TableCommands.new.start_practice(user: Current.user)
    TableChannel.deliver(outcome)
    redirect_to table_path(outcome.table)
  end
end
