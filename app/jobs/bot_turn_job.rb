# Runs a bot's move after its delay, through the table command interface.
class BotTurnJob < ApplicationJob
  queue_as :default

  # The scheduler TableCommands uses by default.
  def self.schedule(game_id:, seat:, version:, delay:)
    set(wait: delay).perform_later(game_id:, seat:, version:)
  end

  def perform(game_id:, seat:, version:)
    TableChannel.deliver(TableCommands.new.bot_turn(game_id:, seat:, version:))
  end
end
