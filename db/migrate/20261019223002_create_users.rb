class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :username, null: false
      t.string :email_address, null: false
      t.string :password_digest, null: false
      t.string :approval_state, null: false, default: "pending"
      t.boolean :admin, null: false, default: false

      t.timestamps
    end
    add_index :users, "lower(username)", unique: true, name: "index_users_on_lower_username"
    add_index :users, :email_address, unique: true
    add_index :users, :approval_state
  end
end
