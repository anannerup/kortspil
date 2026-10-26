class Table
  # "Forlad bordet" at a stored bord. During a spil in progress the player
  # forlader it: a bot takes their seat (Seating#take_over!) and the spil
  # goes on; when the last human forlader, the spil is afbrudt and the bord
  # closes. The tur-ur forlader for a player who stays away (Presence).
  # When the spil ends, the bord closes and everyone moves on to a new
  # bord in the lobby (Playing#spil_over), where standing up is the waiting
  # bord's (WaitingTable#leave), as before the first spil. A stored bord
  # whose spil is over but was not moved on (one from before that) closes.
  module Leaving
    def leave(user:, surroundings: Surroundings.new)
      seated(user) do |game, seat|
        next forlade(game, seat, surroundings) if game.in_progress?

        closed!
        Outcome.new(table: self, messages: humans(seating).map { |human| closed_message(human.user_id) })
      end
    end

    private

    # The seat's player forlader the spil in progress: a bot takes over the
    # seat as its new player (and takes its turn at once if it is to act),
    # or, when they are the last
    # human, the spil is afbrudt and the bord closes. Passively (`due_at`,
    # from the tur-ur) only if the seat is still out of time when it gets
    # the lock.
    def forlade(game, seat, surroundings, due_at: nil)
      leaver, goes_on = game.with_lock do
        occupant = game.seating.occupants.fetch(seat)
        next unless game.in_progress? && occupant.human?
        next if due_at && game.turn_clock.forladt(due_at).exclude?(seat)

        [ occupant.user_id, hand_over(game, seat, occupant.user_id) ]
      end
      return Outcome.new(table: self) unless leaver
      return Outcome.new(table: self, messages: [ closed_message(leaver) ]) unless goes_on

      told = Message.new(seat:, user_id: leaver, payload: { "type" => "forladt" })
      bot = game.seating.occupants.fetch(seat).bot_player
      after = game.bots_to_act.include?(seat) ? bot.take_turn(table: self, game_id: game.id, version: game.version, surroundings:) : runde_going_on(game, surroundings)
      Outcome.new(table: self, messages: [ told, *after.messages ])
    end

    # Under the game's lock: a bot takes the seat over and the spil goes on
    # (true), or the leaver was the last human and the spil is afbrudt
    # (false).
    def hand_over(game, seat, user_id)
      if humans(game.seating).none? { |human| human.seat != seat }
        game.abandon!(forfeited_by: User.find(user_id))
        closed!
        return false
      end

      game.seating = game.seating.take_over!(seat, game:, at_play: game.version)
      true
    end

    def runde_going_on(game, surroundings)
      out_of_turn(game, surroundings)
      schedule(game, surroundings)
      Outcome.new(table: self, messages: state_messages(game, surroundings))
    end
  end
end
