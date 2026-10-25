class Table
  # Presence and the tur-ur (tickets 18 and 19, PLAN.md "Absence and
  # leaving"): at an open bord, clients send heartbeats; a seat whose
  # connection closes or whose heartbeats stop is frakoblet, and one that
  # stays away for 60 seconds, or does not act for 60 seconds on its turn
  # (warned at 30), has forladt: a bot takes the seat (Table::Leaving) and
  # the spil goes on. The rules are TurnClock's; the time comes from the
  # injected clock (Surroundings#now), and #tick, which the scheduler runs
  # (TurnClockJob) when something is next due, applies it. Practice tables
  # have no tur-ur.
  module Presence
    # A user (re)opens the table: they get the full state for their seat.
    # If they were frakoblet, they are back in time and everyone is told. If
    # bots are to act, their turns are scheduled again, in case a job was
    # lost; likewise the next runde after a completed one, and the tur-ur.
    def connect(user:, surroundings: Surroundings.new)
      seated(user) do |game, seat|
        back = seating.occupants.fetch(seat).frakoblet?
        back ? seating.connected!(seat, at: surroundings.now) : seating.heartbeat!(seat, at: surroundings.now)
        schedule(game, surroundings)
        Outcome.new(table: self, messages: back ? state_messages(game, surroundings) : [ state_message(game, seat, user.id, surroundings) ])
      end
    end

    # The client's keep-alive. A seat the tur-ur took for frakoblet while
    # its connection was open after all comes back with it.
    def heartbeat(user:, surroundings: Surroundings.new)
      seated(user) do |_game, seat|
        next connect(user:, surroundings:) if seating.occupants.fetch(seat).frakoblet?

        seating.heartbeat!(seat, at: surroundings.now)
        Outcome.new(table: self)
      end
    end

    # The user's connection to the table closed. During a spil in progress
    # at an open bord they are frakoblet from now on, and the others are
    # told.
    def disconnect(user:, surroundings: Surroundings.new)
      seated(user) do |game, seat|
        next Outcome.new(table: self) unless open? && game.in_progress?

        seating.disconnected!(seat, at: surroundings.now)
        schedule_tick(game, surroundings)
        Outcome.new(table: self, messages: state_messages(game, surroundings).reject { |message| message.seat == seat })
      end
    end

    # The tur-ur's tick in the spil `game_id`: applies what TurnClock says
    # is due now. Seats whose heartbeats stopped are frakoblet, players
    # warned on their turn are told (only them), and seats out of time
    # forlader. Then the next tick is scheduled. A tick that finds nothing
    # due changes nothing.
    def tick(game_id:, surroundings: Surroundings.new)
      game = games.find(game_id)
      at = surroundings.now
      warned, changed = game.with_lock { apply_turn_clock(game, at) }
      return Outcome.new(table: self) unless warned

      changes = changed ? state_messages(game, surroundings) : []
      warnings = warned.map { |seat| warning_message(game, seat, at) }
      forladt = game.turn_clock.forladt(at).map { |seat| forlade(games.find(game_id), seat, surroundings, due_at: at) }
      schedule_tick(games.find(game_id), surroundings)
      Outcome.new(table: self, messages: [ *changes, *warnings, *forladt.flat_map(&:messages) ])
    end

    private

    # Under the game's lock: marks lost connections and warnings on the
    # spil's seating. Returns the seats warned and whether anyone was lost,
    # or nil when no spil is in progress.
    def apply_turn_clock(game, at)
      return unless game.in_progress?

      clock = game.turn_clock
      lost = clock.lost(at)
      seating = game.seating
      lost.each { |seat, since| seating = seating.disconnected!(seat, at: since) }
      warned = clock.to_warn(at)
      warned.each { |seat| seating = seating.warned!(seat, at:) }
      game.seating = seating
      [ warned, lost.any? ]
    end

    # Schedules a tick for when the tur-ur next has something due, unless an
    # earlier one is already coming (games.tick_at), so one chain of ticks
    # runs per spil.
    def schedule_tick(game, surroundings)
      at = game.turn_clock.next_check
      return unless at

      now = surroundings.now
      pending = Game.where(id: game.id).pick(:tick_at)
      return if pending && pending > now && pending <= at

      game.update_columns(tick_at: at)
      surroundings.scheduler.tick(game_id: game.id, delay: [ at - now, 0 ].max.to_f)
    end

    def warning_message(game, seat, at)
      payload = { type: "turn_warning", seconds_left: game.turn_clock.seconds_left(seat, at) }
      Message.new(seat:, user_id: game.seating.occupants.fetch(seat).user_id, payload: payload.as_json)
    end
  end
end
