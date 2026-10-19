class CreateTables < ActiveRecord::Migration[8.1]
  def change
    create_table :tables do |t|
      t.references :host, null: false, foreign_key: { to_table: :users }
      t.string :kind, null: false, default: "practice"
      t.string :status, null: false, default: "waiting"
      t.timestamps
    end
    add_index :tables, :status
  end
end
