# What a bord's actions run later, as jobs (Table::Surroundings#scheduler):
# a bot's turn, the next runde, and the tur-ur's next check. Tests pass a
# fake that records what was scheduled instead (FakeScheduler).
module TableScheduler
  def self.bot_turn(game_id:, seat:, version:)
    BotTurnJob.perform_later(game_id:, seat:, version:)
  end

  def self.next_runde(game_id:, number:, delay:)
    NextRundeJob.set(wait: delay).perform_later(game_id:, number:)
  end

  def self.tick(game_id:, delay:)
    TurnClockJob.set(wait: delay).perform_later(game_id:)
  end
end
