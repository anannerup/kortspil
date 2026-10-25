class Game
  # What each seat of a spil may see, for the "state" message: who sits
  # where, the engine's view for the seat, the score and the tur-ur. The
  # part about the seats is the same for every game; the rest is the
  # game's (#game_state).
  module State
    # Everything the seat may see, built at `now`: for each seat who sits
    # there, whether a bot took it over from a player who forlod, whether it
    # is frakoblet, and the seconds it has left on the tur-ur (TurnClock;
    # nil when none runs).
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
          { seat: occupant.seat, name: occupant.name, bot: occupant.bot?, took_over_from: took_over_from[occupant.seat],
            frakoblet: occupant.frakoblet?, seconds_left: clock.seconds_left(occupant.seat, now) }
        end,
        timer: { warning: TurnClock::WARNING, limit: TurnClock::LIMIT },
        view: engine_round.view_for(seat),
        **game_state
      }
    end

    private

    def game_state = esmakker? ? esmakker_state : hjerterfri_state

    def hjerterfri_state
      { points_taken: engine_round.points_taken, score: }
    end

    # The number of runder the spil lasts, the runde being played (a redeal
    # is the same runde again, so it counts the completed runder, while
    # `round_number` counts the round rows dealt), and the totals so far
    # (scoring comes in ticket 05).
    def esmakker_state
      runde = [ engine_game.results.size + 1, engine_game.runder ].min
      { runder: engine_game.runder, runde:, score: { totals: engine_game.totals } }
    end

    # The score sheet: completed runder with running totals, who leads (the
    # lowest total) and, once the spil is over, the vindere: the humans among
    # the seats with the lowest total. A bot never wins; a human tied with a
    # bot does (GLOSSARY.md, Vinder).
    def score
      totals = engine_game.totals
      leaders = engine_game.results.empty? ? [] : totals.each_index.select { |seat| totals[seat] == totals.min }
      winners = engine_game.winners & human_seats
      { end_score: engine_game.rules.end_score, rows: engine_game.rows, totals:, leaders:, winners: }
    end

    # The name of the player a bot took each seat over from, by seat.
    def took_over_from
      @took_over_from ||= begin
        names = User.where(id: seat_log.map { |entry| entry["from"] }).pluck(:id, :username).to_h
        seat_log.to_h { |entry| [ entry["seat"], names[entry["from"]] ] }
      end
    end
  end
end
