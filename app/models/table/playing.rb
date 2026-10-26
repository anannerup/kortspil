class Table
  # The spil at the bord: a player's action (#act), the spil's deadline
  # (#deadline_passed: at es-makker the end of vip's bank window), the next
  # runde and the end of the spil.
  #
  # A player's action is one way in, whatever the game: #act takes the
  # engine intent of the bord's game (hjerterfri's pass, play and moon
  # choice; es-makker's bidding and play). A human's comes from the client
  # as an action with its data, which the game decodes (#client_intent); a
  # bot (BotPlayer) hands in the intent it chose on its turn. The bord
  # judges and carries them out the same for both.
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
  # a bot that may act out of turn is asked at once (#out_of_turn), and
  # when a runde is complete the next one is dealt after RESULT_PAUSE
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
    # An intent the card game refuses because the spil's deadline passed
    # (Game#past_deadline: at vip a bank after the bank window's time ran
    # out) is refused, even before the deadline's job has run.
    def act(player:, intent:, surroundings: Surroundings.new)
      seated(player) do |game, seat|
        next Outcome.new(table: self) unless intent

        late = game.past_deadline(intent, at: surroundings.now)
        next Outcome.new(table: self, messages: rejection_messages(game, seat, intent, late)) if late

        apply_intent(game, seat, surroundings, intent)
      end
    end

    # The engine intent for a client's action (a TableChannel action and its
    # data, as ClientIntents in the client sends it), decoded by the bord's
    # game. Nil for an action the game does not know.
    def client_intent(action, data) = card_game.client_intent(action, data)

    # The deadline of runde `number` of the spil `game_id` passed (scheduled
    # when it was set, DeadlineJob): the runde takes its card game's step
    # for it (Game#deadline_passed!; at vip the bank window closes and the
    # melder leads the first stik). A repeat, or a job for a deadline gone
    # (the step was taken anyway) or of another runde, does nothing, like a
    # stale bot turn. A job from before the deadline moved (a bank starts
    # the window again) finds it not due yet and schedules the rest instead.
    def deadline_passed(game_id:, number:, surroundings: Surroundings.new)
      game = games.find(game_id)
      passed = game.with_lock do
        next false unless game.in_progress? && game.current_round.number == number && game.deadline_at
        next :early unless game.deadline_due?(surroundings.now)

        game.deadline_passed!(at: surroundings.now)
      end
      schedule_deadline(game, surroundings) if passed == :early
      return Outcome.new(table: self) unless passed == true

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

        game.apply(seat, intent, at: surroundings.now)
      end
      return Outcome.new(table: self) unless result
      return Outcome.new(table: self, messages: rejection_messages(game, seat, intent, result.reason)) if result.rejected?

      acted(game, surroundings)
    end

    # After an accepted step: the spil ends, or the seats wait from now and
    # what is due next is scheduled; everyone gets the new state.
    def acted(game, surroundings)
      return spil_over(game, surroundings) if game.finished?

      out_of_turn(game, surroundings)
      # While the seats act at the same time (the bytte), the bots' turns
      # were scheduled when the runde was dealt, and the tur-ur runs from the
      # deal.
      unless game.simultaneous?
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

    # Bots that may act now though it is not their turn (Game#bots_out_of_turn:
    # at es-makker the melder laying fordækt before a forhånd who is someone
    # else leads) are asked at once, before the seat to act is woken, so
    # they get the chance a human has. The bord wakes bots only on their
    # turn, and the seat to act stays the forhånd's: a bot that does
    # nothing leaves no trace, and one that lays fordækt does what a human
    # may, saved like a turn with its thought kept for "Vis kort". Asked
    # after every step, so after each step that could start the play.
    def out_of_turn(game, surroundings)
      game.bots_out_of_turn.each do |seat|
        decision = game.bot_out_of_turn(seat, level: game.seating.occupants.fetch(seat).bot_level, random: surroundings.random)
        next unless decision

        game.bot_thought!(seat, decision.thought)
        game.with_lock { game.apply(seat, decision.intent, at: surroundings.now) if game.in_progress? }
      end
    end

    # The bots that are to act, the spil's deadline, and the next runde once
    # this one is complete.
    def schedule(game, surroundings)
      scheduler = surroundings.scheduler
      game.bots_to_act.each { |seat| scheduler.bot_turn(game_id: game.id, seat:, version: game.version) }
      schedule_deadline(game, surroundings)
      number = game.next_runde_number
      scheduler.next_runde(game_id: game.id, number:, delay: game.redeal? ? REDEAL_PAUSE : RESULT_PAUSE) if number
      schedule_tick(game, surroundings)
    end

    # While the spil has a deadline, a job takes the runde's step when it
    # passes (#deadline_passed). Scheduled again on a reconnect, in case one
    # was lost; the repeats do nothing.
    def schedule_deadline(game, surroundings)
      return unless game.deadline_at

      delay = [ game.deadline_at - surroundings.now, 0 ].max.to_f
      surroundings.scheduler.deadline(game_id: game.id, number: game.current_round.number, delay:)
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
