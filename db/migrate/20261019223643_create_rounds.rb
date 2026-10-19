class CreateRounds < ActiveRecord::Migration[8.1]
  def change
    create_table :rounds do |t|
      t.references :game, null: false, foreign_key: true, index: false
      t.integer :number, null: false
      t.string :pass_direction, null: false
      t.string :deal, null: false
      t.string :passes, null: false, default: ""
      t.string :plays, null: false, default: ""
      t.timestamps
    end
    add_index :rounds, [ :game_id, :number ], unique: true
  end
end
