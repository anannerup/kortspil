# A bot's turn: wakes the bot in the seat so it takes its turn
# (Table::BotPlayer.wake). A stale or duplicate turn does nothing.
class BotTurnJob < ApplicationJob
  queue_as :default

  def perform(game_id:, seat:, version:)
    TableChannel.deliver(Table::BotPlayer.wake(game_id:, seat:, version:))
  end
end
