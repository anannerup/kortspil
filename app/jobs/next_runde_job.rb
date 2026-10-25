# Deals the next runde after the pause that shows the runde result
# (Table#next_runde).
class NextRundeJob < ApplicationJob
  queue_as :default

  def perform(game_id:, number:)
    TableChannel.deliver(Game.find(game_id).table.next_runde(game_id:, number:))
  end
end
