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

  # Seat rows for a practice bord stored directly: `user` in seat 0 and
  # three bots. Returns the Table::Seating.
  def seat_practice!(table, user)
    table.seating.seat_everyone!(WaitingTable.build(host: user, rules: Rules.standard(kind: "practice")).occupants)
  end
end
