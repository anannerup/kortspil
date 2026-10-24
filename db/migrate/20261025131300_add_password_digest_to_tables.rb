class AddPasswordDigestToTables < ActiveRecord::Migration[8.1]
  def change
    add_column :tables, :password_digest, :string
  end
end
