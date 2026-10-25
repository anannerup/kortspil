# The bord's rules: its own (TableRules: the type, and at es-makker the
# number of runder) and the card game's (GameRules: for hjerterfri the end
# score and house rules, for es-makker Esmakker::Rules). The vært chooses
# them before the spil. A stored bord keeps them in tables.kind,
# tables.runder and tables.rules and never changes them; each spil
# snapshots the game's rules (games.rules).
class Rules < Data.define(:table, :game)
  def self.standard(kind: "open", game: "hjerterfri") = new(table: TableRules.standard(kind:, game:), game: GameRules.standard(game))

  def kind = table.kind
  def runder = table.runder
end
