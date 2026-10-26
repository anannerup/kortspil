class Table
  # "Vis kort" at the bord (Game::VisKort): an admin alone with bots
  # switches it on or off during the spil; anyone else is refused.
  module VisKort
    # The user switches "Vis kort" `on` (true) or off and gets their state
    # again, with or without the bots' hands and thoughts. Refused
    # (:vis_kort_not_allowed) unless the user is an admin and every other
    # seat holds a bot. A user who does not sit here gets nothing.
    def switch_vis_kort(user:, on:, surroundings: Surroundings.new)
      seated(user) do |game, seat|
        next Outcome.new(table: self, refusal: :vis_kort_not_allowed) unless game.vis_kort_allowed?(seat)

        game.seating = game.seating.vis_kort!(seat, on == true)
        Outcome.new(table: self, messages: [ state_message(game, seat, user.id, surroundings) ])
      end
    end
  end
end
