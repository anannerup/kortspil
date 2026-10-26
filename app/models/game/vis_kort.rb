class Game
  # "Vis kort" (docs/bots/esmakker-strategy.md §5, decided with Anders): an
  # admin at a bord where every other seat holds a bot may switch it on
  # (Table#switch_vis_kort). Then their state also carries the bots' hands
  # and each bot's latest thought (what it intended with its last decision,
  # Game#bot_decision), at every game alike. Nobody else ever gets them: not
  # a player who is no admin, and nobody at a bord with another human, even
  # if the switch was left on (a human sat down at the next spil's bord).
  # It shows what the bots know and think; it never changes it.
  module VisKort
    # Whether the human in `seat` may have "Vis kort": an admin, and every
    # other seat holds a bot.
    def vis_kort_allowed?(seat)
      occupants = seating.occupants
      occupant = occupants.fetch(seat)
      occupant.human? && occupant.admin && occupants.count(&:human?) == 1
    end

    # Whether someone at the bord has "Vis kort" on: only then are the
    # bots' thoughts kept (#bot_thought!).
    def vis_kort_watched? = seating.occupants.any? { |occupant| occupant.vis_kort && vis_kort_allowed?(occupant.seat) }

    # The bot in `seat` thought `thought` about its decision: kept for "Vis
    # kort" while someone watches.
    def bot_thought!(seat, thought)
      self.seating = seating.bot_thought!(seat, thought) if vis_kort_watched?
    end

    # What "Vis kort" shows the seat (its state's `vis_kort`): nil unless
    # it may have it (#vis_kort_allowed?); otherwise whether it is on and,
    # when on, each bot's seat, hand and latest thought (nil before its
    # first decision while watched).
    def vis_kort_for(seat)
      return nil unless vis_kort_allowed?(seat)

      on = seating.occupants.fetch(seat).vis_kort
      bots = on ? seating.occupants.select(&:bot?).map { |bot| { seat: bot.seat, hand: engine_round.view_for(bot.seat)[:hand], thought: bot.bot_thought } } : []
      { on:, bots: }
    end
  end
end
