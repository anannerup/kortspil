# Runs the table clock (Table#tick) when something is next due:
# a heartbeat timing out, a turn warning or a deadline.
class TableTickJob < ApplicationJob
  queue_as :default

  def perform(game_id:)
    TableChannel.deliver(Game.find(game_id).table.tick(game_id:))
  end
end
