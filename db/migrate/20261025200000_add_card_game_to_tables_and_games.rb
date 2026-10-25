# Es-makker (ticket 01): a stored bord and its spil record which card game
# they are, a bord its number of runder (es-makker's TableRules), and an
# es-makker runde its kortgiver and action log; it has no bytning. Rows
# stored before are hjerterfri.
class AddCardGameToTablesAndGames < ActiveRecord::Migration[8.1]
  def change
    add_column :tables, :game, :string, null: false, default: "hjerterfri"
    add_column :tables, :runder, :integer
    add_column :games, :game, :string, null: false, default: "hjerterfri"
    add_column :rounds, :dealer, :integer
    add_column :rounds, :actions, :string, null: false, default: ""
    change_column_null :rounds, :pass_direction, true
  end
end
