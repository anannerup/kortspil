class Table
  # A bot in a seat (GLOSSARY.md: Bot): a player that acts for itself, just
  # like a human. On its turn it reads what its seat may see, chooses with
  # its strategy (Hjerterfri::Bot at its `level`, one of
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

      act(table, game, surroundings.strategy(level), surroundings)
    end

    private

    # Passes, chooses the moon or plays, as the runde asks, and hands the
    # intent to the bord like any player (Table#act). At es-makker (no bots
    # in v1) a bot that took over a seat does what the runde gives as its
    # default (Esmakker::Round#default_intent: pas, clubs, the first ace, at
    # vip the first card turned as trump, the kitty laid back, the first
    # legal card), so the spil is not stuck on it; what it should do is
    # ticket 11's.
    def act(table, game, strategy, surroundings)
      table.act(player: self, intent: intent(game, strategy), surroundings:)
    end

    def intent(game, strategy)
      round = game.engine_round
      return round.default_intent(seat) if game.esmakker?

      view = round.view_for(seat)
      return Hjerterfri::Pass.new(cards: strategy.choose_pass(view)) if round.passing?
      return Hjerterfri::MoonChoice.new(option: strategy.choose_moon(seat:, totals: game.engine_game.totals)) if round.choosing_moon?

      engine_game = game.engine_game
      Hjerterfri::Play.new(card: strategy.choose_play(view, totals: engine_game.totals, end_score: engine_game.rules.end_score))
    end
  end
end
