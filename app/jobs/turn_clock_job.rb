# Runs the tur-ur (Table#tick) when something is next due: a heartbeat
# timing out, a turn warning or a deadline (TurnClock).
class TurnClockJob < ApplicationJob
  queue_as :default

  def perform(game_id:)
    TableChannel.deliver(Game.find(game_id).table.tick(game_id:))
  end
end
