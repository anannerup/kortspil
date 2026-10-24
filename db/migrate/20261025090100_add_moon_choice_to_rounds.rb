class AddMoonChoiceToRounds < ActiveRecord::Migration[8.1]
  def change
    add_column :rounds, :moon_choice, :string
  end
end
