class Table
  # The spil at the bord: a player's action (#act), the end of vip's bank
  # window (es-makker), the next runde and the end of the spil.
  #
  # A player's action is one way in, whatever the game: #act takes the
  # engine intent of the bord's game (hjerterfri's pass, play and moon
  # choice; es-makker's bidding and play). A human's comes from the client
  # as an action with its data, which the game decodes (#client_intent); a
  # bot (BotPlayer) hands in the intent it chose on its turn. The bord
  # judges and carries them out the same for both. Es-makker has no bots,
  # except one that takes over the seat of a player who forlader
  # (BotPlayer).
  #
  # Each action loads the spil once (Game, under its row lock, with the
  # bord's Seating) and orchestrates over it: what is due, what to save,
  # what to schedule and whom to tell. Each step is saved before the
  # messages are returned, so only stored state is ever broadcast. An
  # intent the engine rejects is answered to that seat only (to nobody
  # when a bot sits there).
  #
  # Time is the scheduler's job (Surroundings#scheduler, TableScheduler by
  # default): every bot that is to act is woken to take its turn at once
  # (BotTurnJob, BotPlayer#take_turn; the client paces what humans see),
  # and when a runde is complete the next one is dealt after RESULT_PAUSE
  # through #next_runde, so the runde result can be shown; an es-makker
  # runde to be dealt again (Game#redeal?) likewise after REDEAL_PAUSE.
  # The spil ends when the engine's Game says it is over; then everyone at
  # the bord moves on to a new bord in the lobby for the next spil
  # (#spil_over).
  module Playing
    # Seconds the runde result is shown before the next runde is dealt.
    RESULT_PAUSE = 10
    # Seconds an es-makker redeal (everybody passed, or a jernhånd) is shown
    # before the runde is dealt again.
    REDEAL_PAUSE = 5

    # A player acts: passes, plays, makes the moon choice, bids, names
    # trump, banks … — whatever `intent` is, an intent of the bord's game's
    # engine (a client's action decoded by #client_intent, or a bot's
    # choice). The bord applies it to the spil under its lock, saves it,
    # schedules what is due next and tells everyone; the engine judges it,
    # and a rejected intent is answered to that seat only. A player who
    # does not sit here, or no intent (an action the game does not know),
    # changes nothing.
    #
    # At vip a bank after the bank window's time ran out is refused, even
    # before its job has closed it. The first bank starts the window again,
    # so the melder has a whole window to bank back.
    def act(player:, intent:, surroundings: Surroundings.new)
      seated(player) do |game, seat|
        next Outcome.new(table: self) unless intent

        if intent.is_a?(Esmakker::Bank) && game.bank_window_over?(surroundings.now)
          next Outcome.new(table: self, messages: rejection_messages(game, seat, intent, :bank_window_closed))
        end

        apply_intent(game, seat, surroundings, intent)
      end
    end

    # The engine intent for a client's action (a TableChannel action and its
    # data, as ClientIntents in the client sends it), decoded by the bord's
    # game. Nil for an action the game does not know.
    def client_intent(action, data) = (esmakker? ? Esmakker::Round : Hjerterfri::Round).client_intent(action, data)

    # The bank window of runde `number` of the spil `game_id` closes: its
    # time ran out (scheduled when it opened, BankWindowJob). The melder
    # leads the first stik. A repeat, or a job for a window already closed
    # (by the second bank) or of another runde, does nothing, like a stale
    # bot turn. A job from before the window started again (the first bank)
    # finds its time not out yet and schedules the rest instead.
    def close_bank_window(game_id:, number:, surroundings: Surroundings.new)
      game = games.find(game_id)
      closed = game.with_lock do
        next false unless game.in_progress? && game.current_round.number == number && game.banking?
        next :early unless game.bank_window_over?(surroundings.now)

        game.apply(game.engine_round.play.melder, Esmakker::CloseBankWindow.new)
        game.track_bank_window!(at: surroundings.now)
        true
      end
      schedule_bank_window(game, surroundings) if closed == :early
      return Outcome.new(table: self) unless closed == true

      acted(game, surroundings)
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
    def apply_intent(game, seat, surroundings, intent)
      result = game.with_lock do
        next unless game.in_progress?

        game.apply(seat, intent).tap { |applied| game.track_bank_window!(at: surroundings.now, restart: intent.is_a?(Esmakker::Bank)) if applied.accepted? }
      end
      return Outcome.new(table: self) unless result
      return Outcome.new(table: self, messages: rejection_messages(game, seat, intent, result.reason)) if result.rejected?

      acted(game, surroundings)
    end

    # After an accepted step: the spil ends, or the seats wait from now and
    # what is due next is scheduled; everyone gets the new state.
    def acted(game, surroundings)
      return spil_over(game, surroundings) if game.finished?

      # Bots' passes were scheduled when the runde was dealt, and the tur-ur
      # of the pass runs from the deal.
      unless game.engine_round.passing?
        game.turn_started!(at: surroundings.now)
        schedule(game, surroundings)
      end
      Outcome.new(table: self, messages: state_messages(game, surroundings))
    end

    # The spil is over (Anders, 2026-10-26: everyone goes out to the lobby
    # to a new spil together). The stored bord closes, and everyone at it,
    # bots with their levels, waits for the next spil at a new bord in the
    # lobby (WaitingTable.after_spil) with the same seats, vært, game, rules,
    # password and chat. There each sits down to play again or stands up,
    # and the vært starts when every seat is taken. Each human gets the
    # final state with the new bord's path (`next_path`), so the result is
    # shown before they go on.
    def spil_over(game, surroundings)
      waiting = with_lock do
        next if closed?

        WaitingTable.after_spil(self, seating.occupants).tap do |after|
          surroundings.chat.move(id, after.id)
          closed!
        end
      end
      return Outcome.new(table: self) unless waiting

      surroundings.waiting_tables.add(waiting)
      next_path = "/borde/#{waiting.id}"
      messages = humans(game.seating).map { |human| state_message(game, human.seat, human.user_id, surroundings, next_path:) }
      Outcome.new(table: self, messages:)
    end

    # The bots that are to act, the end of an open bank window, and the
    # next runde once this one is complete.
    def schedule(game, surroundings)
      scheduler = surroundings.scheduler
      game.bots_to_act.each { |seat| scheduler.bot_turn(game_id: game.id, seat:, version: game.version) }
      schedule_bank_window(game, surroundings)
      number = game.next_runde_number
      scheduler.next_runde(game_id: game.id, number:, delay: game.redeal? ? REDEAL_PAUSE : RESULT_PAUSE) if number
      schedule_tick(game, surroundings)
    end

    # While vip's bank window is open, a job closes it when its time runs
    # out (#close_bank_window). Scheduled again on a reconnect, in case one
    # was lost; the repeats do nothing.
    def schedule_bank_window(game, surroundings)
      return unless game.banking? && game.bank_closes_at

      delay = [ game.bank_closes_at - surroundings.now, 0 ].max.to_f
      surroundings.scheduler.close_bank_window(game_id: game.id, number: game.current_round.number, delay:)
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
