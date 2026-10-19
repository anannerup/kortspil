class CreateGames < ActiveRecord::Migration[8.1]
  def change
    create_table :games do |t|
      t.references :table, null: false, foreign_key: true
      t.json :rules, null: false, default: {}
      t.string :status, null: false, default: "in_progress"
      t.json :seats, null: false, default: []
      t.json :seat_log, null: false, default: []
      t.timestamps
    end
  end
end
