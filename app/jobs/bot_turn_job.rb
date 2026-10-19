# Runs a bot's move after its delay, through the table command interface.
class BotTurnJob < ApplicationJob
  queue_as :default

  def perform(game_id:, seat:, version:)
    TableChannel.deliver(TableCommands.new.bot_turn(game_id:, seat:, version:))
  end
end
