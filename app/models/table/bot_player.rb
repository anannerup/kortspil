class Table
  # A bot in a seat (GLOSSARY.md: Bot): a player that acts for itself, just
  # like a human. On its turn it reads what its seat may see, chooses with
  # its strategy (Hjerterfri::Bot at its `level`, one of
  # Hjerterfri::Bot::LEVELS) and performs the action through the bord's
  # ordinary actions: #pass, #play and #choose_moon, the same ones a human
  # uses. The bord judges and carries them out and does not know who made
  # them.
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

    # Passes, chooses the moon or plays, as the runde asks. At es-makker
    # (no bots in v1) a bot that took over a seat does what the runde
    # gives as its default (Esmakker::Round#default_intent: pas, clubs, the
    # first ace, the kitty laid back, the first legal card), so the spil is
    # not stuck on it; what it should do is ticket 11's.
    def act(table, game, strategy, surroundings)
      return act_esmakker(table, game.engine_round.default_intent(seat), surroundings) if game.esmakker?

      round = game.engine_round
      view = round.view_for(seat)
      if round.passing?
        table.pass(player: self, cards: strategy.choose_pass(view), surroundings:)
      elsif round.choosing_moon?
        table.choose_moon(player: self, option: strategy.choose_moon(seat:, totals: game.engine_game.totals), surroundings:)
      else
        engine_game = game.engine_game
        table.play(player: self, card: strategy.choose_play(view, totals: engine_game.totals, end_score: engine_game.rules.end_score), surroundings:)
      end
    end

    def act_esmakker(table, intent, surroundings)
      case intent
      when Esmakker::ChooseTrump then table.choose_trump(player: self, trump: intent.trump.to_s, surroundings:)
      when Esmakker::CallAce then table.call_ace(player: self, suit: intent.suit, surroundings:)
      when Esmakker::Discard then table.discard(player: self, cards: intent.cards.map(&:to_s), surroundings:)
      when Esmakker::PlayCard then table.play(player: self, card: intent.card.to_s, surroundings:)
      else table.pas(player: self, surroundings:)
      end
    end
  end
end
