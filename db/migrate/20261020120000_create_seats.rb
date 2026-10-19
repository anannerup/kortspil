# A bord's four seats as rows, so seats exist before a spil and "where does
# this user sit" is an indexed query. See docs/adr/0001-seats-table.md.
class CreateSeats < ActiveRecord::Migration[8.1]
  def change
    create_table :seats do |t|
      t.references :table, null: false, foreign_key: true, index: false
      t.integer :position, null: false
      t.references :user, foreign_key: true
      t.string :bot_name
      t.timestamps
    end
    add_index :seats, [ :table_id, :position ], unique: true
    add_check_constraint :seats, "position BETWEEN 0 AND 3", name: "seats_position_range"
    add_check_constraint :seats, "user_id IS NULL OR bot_name IS NULL", name: "seats_one_occupant"
  end
end
