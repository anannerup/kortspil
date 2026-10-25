# The bord's rules: its own (TableRules: the type) and the card game's
# (GameRules: for hjerterfri the end score and house rules). The vært
# chooses them before the spil. A stored bord keeps them in tables.kind and
# tables.rules and never changes them; each spil snapshots the game's rules
# (games.rules).
class Rules < Data.define(:table, :game)
  def self.standard(kind: "open", game: "hjerterfri") = new(table: TableRules.new(kind:), game: GameRules.standard(game))

  def kind = table.kind
end
