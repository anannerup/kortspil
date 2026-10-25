class Table
  # The spil at the bord: passing, playing, the moon choice, the next runde
  # and "Spil igen".
  #
  # Passing, playing and the moon choice are a player's: a human (their
  # User) or a bot (BotPlayer, which acts through these same actions on its
  # turn). The bord judges and carries them out the same for both.
  #
  # Each action loads the spil once (Game, under its row lock, with the
  # bord's Seating) and orchestrates over it: what is due, what to save,
  # what to schedule and whom to tell. Each pass and play is saved before
  # the messages are returned, so only stored state is ever broadcast. A
  # pass, play or moon choice the engine rejects is answered to that seat
  # only (to nobody when a bot sits there).
  #
  # Time is the scheduler's job (Surroundings#scheduler, TableScheduler by
  # default): every bot that is to act is woken to take its turn at once
  # (BotTurnJob, BotPlayer#take_turn; the client paces what humans see),
  # and when a runde is complete the next one is dealt after RESULT_PAUSE
  # through #next_runde, so the runde result can be shown. The spil ends
  # when the engine's Game says it is over.
  module Playing
    # Seconds the runde result is shown before the next runde is dealt.
    RESULT_PAUSE = 10

    # The player passes three cards (the bytte).
    def pass(player:, cards:, surroundings: Surroundings.new)
      seated(player) { |game, seat| act(game, seat, surroundings, Hjerterfri::Pass.new(cards:)) }
    end

    # The player plays a card.
    def play(player:, card:, surroundings: Surroundings.new)
      seated(player) { |game, seat| act(game, seat, surroundings, Hjerterfri::Play.new(card:)) }
    end

    # The moon shooter chooses under shooter's choice (Hjerterfri::MoonChoice).
    def choose_moon(player:, option:, surroundings: Surroundings.new)
      seated(player) { |game, seat| act(game, seat, surroundings, Hjerterfri::MoonChoice.new(option:)) }
    end

    # Deals runde `number` of the spil `game_id` once the runde before it is
    # complete and the spil goes on. Scheduled after a runde ends; a repeat
    # does nothing.
    def next_runde(game_id:, number:, surroundings: Surroundings.new)
      game = games.find(game_id)
      dealt = game.with_lock do
        next false unless game.next_runde_number == number

        game.deal_next!(shuffler: surroundings.shuffler)
        true
      end
      return Outcome.new(table: self) unless dealt

      runde_started(game, surroundings)
    end

    # A seated user does not want to wait out the pause after a runde.
    def deal_next_runde(user:, surroundings: Surroundings.new)
      seated(user) { |game, _seat| next_runde(game_id: game.id, number: game.current_round.number + 1, surroundings:) }
    end

    # "Spil igen" once the current spil is finished: the user asks for
    # another (Game#ask_to_play_again!). When every human at the table has
    # asked, a new spil starts with the same seats and the table's rules;
    # until then every seat is told who has asked (state
    # `play_again_seats`). At a practice table the one human's ask starts it
    # at once.
    def play_again(user:, surroundings: Surroundings.new)
      seated(user) do |_game, _seat|
        started, game = with_lock do
          current = current_game
          next unless current.finished? && playing?

          current.ask_to_play_again!(user)
          next [ false, current ] unless current.everyone_asked_to_play_again?(seating)

          [ true, Game.start!(table: self, rules: rules.game, shuffler: surroundings.shuffler) ]
        end
        next Outcome.new(table: self) unless game

        started ? runde_started(game, surroundings) : Outcome.new(table: self, messages: state_messages(game, surroundings))
      end
    end

    # A runde of `game` was dealt: the spil waits for the seats to act from
    # now, the bots' turns are scheduled, and every seat gets its state.
    def runde_started(game, surroundings)
      game.turn_started!(at: surroundings.now)
      schedule(game, surroundings)
      Outcome.new(table: self, messages: state_messages(game, surroundings))
    end

    private

    # Applies the seat's intent to the spil under its lock and saves the
    # result before answering.
    def act(game, seat, surroundings, intent)
      result = game.with_lock { game.apply(seat, intent) if game.in_progress? }
      return Outcome.new(table: self) unless result
      return Outcome.new(table: self, messages: rejection_messages(game, seat, intent, result.reason)) if result.rejected?

      # Bots' passes were scheduled when the runde was dealt, and the tur-ur
      # of the pass runs from the deal.
      unless game.engine_round.passing?
        game.turn_started!(at: surroundings.now)
        schedule(game, surroundings)
      end
      Outcome.new(table: self, messages: state_messages(game, surroundings))
    end

    # The bots that are to act, and the next runde once this one is complete.
    def schedule(game, surroundings)
      scheduler = surroundings.scheduler
      game.bots_to_act.each { |seat| scheduler.bot_turn(game_id: game.id, seat:, version: game.version) }
      number = game.next_runde_number
      scheduler.next_runde(game_id: game.id, number:, delay: RESULT_PAUSE) if number
      schedule_tick(game, surroundings)
    end

    # A rejected intent is answered to the seat only, when a human sits
    # there.
    def rejection_messages(game, seat, intent, reason)
      occupant = game.seating.occupants.fetch(seat)
      return [] unless occupant.human?

      payload = { type: "rejected", reason:, **intent.to_h }
      [ Message.new(seat:, user_id: occupant.user_id, payload: payload.as_json) ]
    end
  end
end
