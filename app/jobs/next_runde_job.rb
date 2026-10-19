# Deals the next runde after the pause that shows the runde result.
class NextRundeJob < ApplicationJob
  queue_as :default

  def perform(game_id:, number:)
    TableChannel.deliver(TableCommands.new.next_runde(game_id:, number:))
  end
end
