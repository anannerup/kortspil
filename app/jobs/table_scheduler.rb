# The scheduler TableCommands uses by default: it runs table commands later
# as jobs. Tests pass a fake that records what was scheduled instead.
module TableScheduler
  def self.bot_turn(game_id:, seat:, version:, delay:)
    BotTurnJob.set(wait: delay).perform_later(game_id:, seat:, version:)
  end

  def self.next_runde(game_id:, number:, delay:)
    NextRundeJob.set(wait: delay).perform_later(game_id:, number:)
  end
end
