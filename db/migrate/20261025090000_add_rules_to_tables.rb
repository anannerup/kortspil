class AddRulesToTables < ActiveRecord::Migration[8.1]
  def change
    add_column :tables, :rules, :json, default: {}, null: false
  end
end
