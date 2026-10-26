class Table
  # A bot in a seat (GLOSSARY.md: Bot): a player that acts for itself, just
  # like a human. On its turn it chooses as its card game's bot does at its
  # `level` (Game#bot_intent; at hjerterfri Hjerterfri::Bot, one of
  # Hjerterfri::Bot::LEVELS) and hands the intent to the bord's one way in
  # for a player's action (Table#act), the same a human's goes through. The
  # bord judges and carries it out and does not know who made it.
  #
  # The seat holds the bot's level (Seating::Occupant#bot_level). A bot that
  # takes over from a player who forlader is simply a new player in the seat
  # (Seating#take_over!) and plays on from the next move.
  #
  # Bots never wait: the bord schedules a turn for every bot that is to act
  # (Surroundings#scheduler, BotTurnJob), and the client paces what humans
  # see.
  BotPlayer = Data.define(:seat, :level) do
    # Wakes the bot in `seat` of the spil `game_id` to take the turn
    # scheduled at `version` (what BotTurnJob runs). Nothing happens when the
    # seat holds no bot.
    def self.wake(game_id:, seat:, version:, surroundings: Surroundings.new)
      table = Game.find(game_id).table
      bot = table.seating.occupants.fetch(seat).bot_player
      bot ? bot.take_turn(table:, game_id:, version:, surroundings:) : Outcome.new(table:)
    end

    # Takes its turn in the spil `game_id` at `table`, scheduled at `version`.
    # A turn that is no longer due (Game#bot_turn_due?: a duplicate or stale
    # one) does nothing.
    def take_turn(table:, game_id:, version:, surroundings: Surroundings.new)
      game = table.games.find(game_id)
      return Outcome.new(table:) unless game.in_progress? && game.bot_turn_due?(seat, version)

      act(table, game, surroundings)
    end

    private

    # Does what its card game's bot does on its turn (Game#bot_intent:
    # hjerterfri's strategy at its level; es-makker's default) and hands the
    # intent to the bord like any player (Table#act).
    def act(table, game, surroundings)
      intent = game.bot_intent(seat, level:, random: surroundings.random)
      table.act(player: self, intent:, surroundings:)
    end
  end
end
