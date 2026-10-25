# Runs a bot's move at its bord (Table#bot_turn).
class BotTurnJob < ApplicationJob
  queue_as :default

  def perform(game_id:, seat:, version:)
    TableChannel.deliver(Game.find(game_id).table.bot_turn(game_id:, seat:, version:))
  end
end
