# The spil's deadline passed (Table#deadline_passed): the runde takes its
# card game's step for it (at es-makker vip's bank window closes). A repeat,
# or one for a deadline gone, does nothing.
class DeadlineJob < ApplicationJob
  queue_as :default

  def perform(game_id:, number:)
    TableChannel.deliver(Game.find(game_id).table.deadline_passed(game_id:, number:))
  end
end
