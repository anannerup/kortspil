class Table
  # The spil at the bord: passing, playing, the moon choice (hjerterfri),
  # the meldingsrunde's bid, pas, "det kan jeg selv", gå med and jernhånd,
  # and the melder's trump, called ace, vip's kitty turns, the three cards
  # laid away and fordækt (es-makker), the next runde and the end of the spil. Playing a card is both
  # games'.
  #
  # Passing, playing, the moon choice and the bidding are a player's: a
  # human (their User) or a bot (BotPlayer, which acts through these same
  # actions on its turn). The bord judges and carries them out the same for
  # both. Es-makker has no bots, except one that takes over the seat of a
  # player who forlader (BotPlayer).
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

    # The player passes three cards (the bytte).
    def pass(player:, cards:, surroundings: Surroundings.new)
      seated(player) { |game, seat| act(game, seat, surroundings, Hjerterfri::Pass.new(cards:)) }
    end

    # The player plays a card (its code; at es-makker a code that is no
    # card is rejected as not in the hand).
    def play(player:, card:, surroundings: Surroundings.new)
      seated(player) do |game, seat|
        intent = game.esmakker? ? Esmakker::PlayCard.new(card: parse_card(card)) : Hjerterfri::Play.new(card:)
        act(game, seat, surroundings, intent)
      end
    end

    # The moon shooter chooses under shooter's choice (Hjerterfri::MoonChoice).
    def choose_moon(player:, option:, surroundings: Surroundings.new)
      seated(player) { |game, seat| act(game, seat, surroundings, Hjerterfri::MoonChoice.new(option:)) }
    end

    # --- Es-makker's meldingsrunde (Esmakker::Bidding) ---

    # The player bids a melding, by its code ("9", "10halve", "sol"). A code
    # that is no melding is rejected like a melding not on the ladder.
    def bid(player:, melding:, surroundings: Surroundings.new)
      seated(player) { |game, seat| act(game, seat, surroundings, Esmakker::Bidding::Bid.new(melding: parse_melding(melding))) }
    end

    # The player says pas: out of the bidding for the rest of the runde.
    def pas(player:, surroundings: Surroundings.new)
      seated(player) { |game, seat| act(game, seat, surroundings, Esmakker::Bidding::Pas.new) }
    end

    # The holder takes over the melding the challenger just bid.
    def det_kan_jeg_selv(player:, surroundings: Surroundings.new)
      seated(player) { |game, seat| act(game, seat, surroundings, Esmakker::Bidding::DetKanJegSelv.new) }
    end

    # The player goes with the sol-melding.
    def gaa_med(player:, surroundings: Surroundings.new)
      seated(player) { |game, seat| act(game, seat, surroundings, Esmakker::Bidding::GaaMed.new) }
    end

    # The player claims a jernhånd before the first bid, on their turn or
    # not: the runde is dealt again.
    def claim_jernhaand(player:, surroundings: Surroundings.new)
      seated(player) { |game, seat| act(game, seat, surroundings, Esmakker::Bidding::ClaimJernhaand.new) }
    end

    # --- Es-makker's play of a stik melding (Esmakker::Play) ---

    # The declarer names trump: a suit ("C", "D", "H", "S") or "trumfloes".
    # She is the melder; at halve the holder of the called ace (or the
    # melder, as selvmakker), who then takes the kitty up.
    def choose_trump(player:, trump:, surroundings: Surroundings.new)
      seated(player) { |game, seat| act(game, seat, surroundings, Esmakker::ChooseTrump.new(trump: parse_trump(trump))) }
    end

    # The melder calls an ace by its suit, and takes the kitty up (at halve
    # the ace's holder gives herself away instead).
    def call_ace(player:, suit:, surroundings: Surroundings.new)
      seated(player) { |game, seat| act(game, seat, surroundings, Esmakker::CallAce.new(suit: suit.to_s)) }
    end

    # At vip the melder turns the kitty's next card face up for everyone
    # ("Vend kort"); the third is trump in any case.
    def turn_card(player:, surroundings: Surroundings.new)
      seated(player) { |game, seat| act(game, seat, surroundings, Esmakker::TurnCard.new) }
    end

    # At vip the melder takes the card she turned last as trump ("Det er
    # trumf"), and takes the kitty up.
    def accept_trump(player:, surroundings: Surroundings.new)
      seated(player) { |game, seat| act(game, seat, surroundings, Esmakker::AcceptTrump.new) }
    end

    # The declarer lays three cards away (their codes) that nobody sees.
    def discard(player:, cards:, surroundings: Surroundings.new)
      seated(player) { |game, seat| act(game, seat, surroundings, Esmakker::Discard.new(cards: Array(cards).map { |card| parse_card(card) })) }
    end

    # The melder lays a card (its code) fordækt: face down, counting as the
    # called ace's suit. She plays it later with #play, by the same code.
    def lay_fordaekt(player:, card:, surroundings: Surroundings.new)
      seated(player) { |game, seat| act(game, seat, surroundings, Esmakker::LayFordaekt.new(card: parse_card(card))) }
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
    def act(game, seat, surroundings, intent)
      result = game.with_lock { game.apply(seat, intent) if game.in_progress? }
      return Outcome.new(table: self) unless result
      return Outcome.new(table: self, messages: rejection_messages(game, seat, intent, result.reason)) if result.rejected?
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

    # The bots that are to act, and the next runde once this one is complete.
    def schedule(game, surroundings)
      scheduler = surroundings.scheduler
      game.bots_to_act.each { |seat| scheduler.bot_turn(game_id: game.id, seat:, version: game.version) }
      number = game.next_runde_number
      scheduler.next_runde(game_id: game.id, number:, delay: game.redeal? ? REDEAL_PAUSE : RESULT_PAUSE) if number
      schedule_tick(game, surroundings)
    end

    def parse_melding(code)
      Esmakker::Melding.parse(code)
    rescue ArgumentError
      nil
    end

    def parse_card(code) = Esmakker::Card.valid?(code) ? Esmakker::Card.parse(code) : nil
    def parse_trump(code) = Esmakker::Trump.valid?(code) ? Esmakker::Trump.parse(code) : nil

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
