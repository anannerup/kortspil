class CreateFriendships < ActiveRecord::Migration[8.1]
  def change
    create_table :friendships do |t|
      t.references :requester, null: false, foreign_key: { to_table: :users }
      t.references :addressee, null: false, foreign_key: { to_table: :users }
      t.string :state, null: false, default: "pending"
      t.timestamps
    end

    # One friendship per pair of users, whichever of them asked.
    add_index :friendships, "min(requester_id, addressee_id), max(requester_id, addressee_id)",
      unique: true, name: "index_friendships_on_user_pair"
    add_check_constraint :friendships, "requester_id <> addressee_id", name: "friendships_not_self"
  end
end
