# A practice table whose first spil has started: made waiting (in memory),
# then started by its player, which stores it (TableCommands#start_practice,
# #start).
module PracticeSpil
  def started_practice(user, commands: TableCommands.new, rules: Hjerterfri::Rules.standard)
    waiting = commands.start_practice(user:, rules:).table
    commands.start(table: waiting, user:).table.reload
  end

  # Seat rows for a practice bord stored directly: `user` in seat 0 and
  # three bots. Returns the Table::Seating.
  def seat_practice!(table, user)
    table.seating.seat_everyone!(WaitingTable.create(host: user, kind: :practice, rules: Hjerterfri::Rules.standard).occupants)
  end
end
