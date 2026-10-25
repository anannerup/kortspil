class Table
  # "Forlad bordet" at a stored bord. During a spil in progress the player
  # forlader it: a bot takes their seat (Seating#take_over!) and the spil
  # goes on; when the last human forlader, the spil is afbrudt and the bord
  # closes. The tur-ur forlader for a player who stays away (Presence).
  # Once the spil is over, leaving is standing up: no loss, and the others
  # wait for the next spil at a new bord in the lobby. Standing up before
  # the start is the waiting bord's (WaitingTable#leave).
  module Leaving
    def leave(user:, surroundings: Surroundings.new)
      seated(user) do |game, seat|
        game.in_progress? ? forlade(game, seat, surroundings) : stand_after_spil(user, surroundings)
      end
    end

    private

    # Standing up once the spil is over: no loss. The stored bord closes
    # (its seat rows stay, as for every closed bord). The others, if any
    # humans are left (never at a practice table), wait for the next spil at
    # a new bord in the lobby with the same seats, type and rules, the next
    # human in seat order as vært if the vært left, and the chat; they are
    # told to go there.
    def stand_after_spil(user, surroundings)
      waiting = with_lock do
        after = waiting_after_spil(user)
        surroundings.chat.move(id, after.id) if after
        closed!
        after
      end
      return Outcome.new(table: self, messages: [ closed_message(user.id) ]) unless waiting

      surroundings.waiting_tables.add(waiting)
      payload = { "type" => "waiting", "path" => "/borde/#{waiting.id}" }
      others = waiting.humans.map { |human| Message.new(seat: human.seat, user_id: human.user_id, payload:) }
      Outcome.new(table: self, messages: [ closed_message(user.id), *others ])
    end

    # The bord the others wait at once `user` stood up, or nil if no human
    # is left.
    def waiting_after_spil(user)
      seat = seating.seat_of(user)
      left = seating.occupants.map { |occupant| occupant.seat == seat ? occupant.with(user_id: nil, name: nil) : occupant }
      humans = left.select(&:human?)
      return nil if humans.empty?

      next_host_id = host_id == user.id ? humans.min_by { |human| (human.seat - seat) % Seating::SEAT_COUNT }.user_id : host_id
      WaitingTable.after_spil(self, left).with(host_id: next_host_id)
    end

    # The seat's player forlader the spil in progress: a bot takes over the
    # seat (and acts at once if it is to act), or, when they are the last
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
      after = game.bots_to_act.include?(seat) ? bot_turn(game_id: game.id, seat:, version: game.version, surroundings:) : runde_going_on(game, surroundings)
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
      schedule(game, surroundings)
      Outcome.new(table: self, messages: state_messages(game, surroundings))
    end
  end
end
