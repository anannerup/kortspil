# A practice table whose first spil has started: made waiting (in memory),
# then started by its player, which stores it (WaitingTable.set_up_practice,
# WaitingTable#start). The deal and the bots' lots are seeded, so the
# same cards come every run.
module PracticeSpil
  def started_practice(user, surroundings: Table::Surroundings.new(shuffler: Random.new(0), random: Random.new(0)), rules: Hjerterfri::Rules.standard)
    return stored_practice(user, rules:, surroundings:) unless rules == rules.for_bots

    waiting = WaitingTable.set_up_practice(user:, rules:, surroundings:).table
    waiting.start(user:, surroundings:).table.reload
  end

  # A practice bord whose spil started with `rules` other than husets
  # regler, which no waiting bord with a bot can hold (WaitingTable#initialize):
  # stored directly, as Table.store! does, for the engine's house rules
  # with bots at the bord, as when a bot takes over a leaver's seat in a
  # spil among humans (Seating#take_over!).
  def stored_practice(user, rules:, surroundings:)
    table = Table.create!(game: "hjerterfri", host: user, rules: Rules.new(table: TableRules.new(kind: "practice"), game: rules), status: :playing)
    seat_practice!(table, user).heard_from_all!(at: surroundings.now)
    game = Game.start!(table:, rules: table.rules.game, shuffler: surroundings.shuffler)
    table.runde_started(game, surroundings)
    table.reload
  end

  # An es-makker bord with bots, stored directly with its spil started:
  # the app seats no bot at es-makker (EsmakkerSpil.bots?), but the bord
  # still plays the bots it holds (Esmakker::Bot, Esmakker::Svaer), which
  # the training measures against. `humans` sit in seat order from seat 0
  # (the first is vært), bots at `levels` in the rest. The spil plays by
  # husets regler, as any spil with a bot.
  def stored_esmakker_with_bots(humans, surroundings:, levels: [ :mellem ] * (4 - humans.size), kind: "practice", runder: TableRules::STANDARD_RUNDER)
    occupants = humans.each_with_index.map { |user, seat| Table::Seating::Occupant.new(seat:, user_id: user.id, name: user.username) }
    occupants += levels.each.with_index(humans.size).map { |level, seat| Table::Seating::Occupant.new(seat:, user_id: nil, name: "Bot #{seat}", bot_level: level.to_sym) }
    rules = Rules.new(table: TableRules.new(kind:, runder:), game: Esmakker::Rules.standard)
    table = Table.create!(game: "esmakker", host: humans.first, rules:, status: :playing)
    table.seating.seat_everyone!(occupants).heard_from_all!(at: surroundings.now)
    game = Game.start!(table:, rules: table.rules.game, shuffler: surroundings.shuffler)
    table.runde_started(game, surroundings)
    table.reload
  end

  # A bot takes the seat over in the spil in progress, as one did when a
  # player forlod an es-makker spil before es-makker lost its bots: the
  # seat log and the bot's level (Table::Seating#take_over!). Nothing is
  # scheduled; the test wakes the bot.
  def bot_takes_over(table, seat)
    game = table.current_game
    table.seating.take_over!(seat, game:, at_play: game.version)
    Game.find(game.id)
  end

  # Seat rows for a practice bord stored directly: `user` in seat 0 and
  # three bots. Returns the Table::Seating.
  def seat_practice!(table, user)
    table.seating.seat_everyone!(WaitingTable.build(host: user, rules: Rules.standard(kind: "practice")).occupants)
  end
end
