# The spil's deadline is its card game's (at es-makker vip's bank window
# closing); the spil only keeps when it is.
class RenameBankClosesAtToDeadlineAt < ActiveRecord::Migration[8.1]
  def change
    rename_column :games, :bank_closes_at, :deadline_at
  end
end
