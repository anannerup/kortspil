# Runs the table clock (TableCommands#tick) when something is next due:
# a heartbeat timing out, a turn warning or a deadline.
class TableTickJob < ApplicationJob
  queue_as :default

  def perform(game_id:)
    TableChannel.deliver(TableCommands.new.tick(game_id:))
  end
end
