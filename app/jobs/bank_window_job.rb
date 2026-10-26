# Closes vip's bank window when its time runs out (Table#close_bank_window).
# A repeat, or one for a window already closed, does nothing.
class BankWindowJob < ApplicationJob
  queue_as :default

  def perform(game_id:, number:)
    TableChannel.deliver(Game.find(game_id).table.close_bank_window(game_id:, number:))
  end
end
