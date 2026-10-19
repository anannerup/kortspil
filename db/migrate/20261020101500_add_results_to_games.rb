class AddResultsToGames < ActiveRecord::Migration[8.1]
  def change
    add_column :games, :final_scores, :json, default: [], null: false
    add_reference :games, :forfeited_by, foreign_key: { to_table: :users }, null: true
  end
end
