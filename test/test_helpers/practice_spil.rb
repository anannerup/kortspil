# A practice table whose first spil has started: made waiting (in memory),
# then started by its player, which stores it (WaitingTable.set_up_practice,
# WaitingTable#start).
module PracticeSpil
  def started_practice(user, surroundings: Table::Surroundings.new, rules: Hjerterfri::Rules.standard)
    waiting = WaitingTable.set_up_practice(user:, rules:, surroundings:).table
    waiting.start(user:, surroundings:).table.reload
  end

  # Seat rows for a practice bord stored directly: `user` in seat 0 and
  # three bots. Returns the Table::Seating.
  def seat_practice!(table, user)
    table.seating.seat_everyone!(WaitingTable.build(host: user, rules: Rules.standard(kind: "practice")).occupants)
  end
end
