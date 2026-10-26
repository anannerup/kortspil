class Game
  # What each seat of a spil may see, for the "state" message: who sits
  # where, the engine's view for the seat, the score and the tur-ur. The
  # part about the seats is the same for every game; the rest is the
  # game's (#game_state).
  module State
    # Everything the seat may see, built at `now`: for each seat who sits
    # there (a bot with its level), whether a bot took it over from a player
    # who forlod, whether it is frakoblet, and the seconds it has left on
    # the tur-ur (TurnClock; nil when none runs).
    def state_for(seat, now:)
      clock = turn_clock
      {
        table_id:,
        table_kind: table.kind,
        game:,
        game_id: id,
        status:,
        round_number: current_round.number,
        version:,
        rules: engine_game.rules.to_h,
        seats: seating.occupants.map do |occupant|
          { seat: occupant.seat, name: occupant.name, bot: occupant.bot?, bot_level: occupant.bot_level, took_over_from: took_over_from[occupant.seat],
            frakoblet: occupant.frakoblet?, seconds_left: clock.seconds_left(occupant.seat, now) }
        end,
        timer: { warning: TurnClock::WARNING, limit: TurnClock::LIMIT },
        view: engine_round.view_for(seat),
        **game_state(now)
      }
    end

    private

    # What only the spil's card game shows (HjerterfriSpil.state,
    # EsmakkerSpil.state).
    def game_state(now) = card_game.state(self, now:)

    # The name of the player a bot took each seat over from, by seat.
    def took_over_from
      @took_over_from ||= begin
        names = User.where(id: seat_log.map { |entry| entry["from"] }).pluck(:id, :username).to_h
        seat_log.to_h { |entry| [ entry["seat"], names[entry["from"]] ] }
      end
    end
  end
end
