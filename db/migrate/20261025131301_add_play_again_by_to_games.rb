class AddPlayAgainByToGames < ActiveRecord::Migration[8.1]
  def change
    add_column :games, :play_again_by, :json, default: [], null: false
  end
end
