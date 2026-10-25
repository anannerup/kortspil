# A practice table whose first spil has started: created waiting, then
# started by its player (TableCommands#start_practice, #start).
module PracticeSpil
  def started_practice(user, commands: TableCommands.new, rules: Hjerterfri::Rules.standard)
    table = commands.start_practice(user:, rules:).table
    commands.start(table:, user:)
    table.reload
  end
end
