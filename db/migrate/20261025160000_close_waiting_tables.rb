# A bord is stored only once its spil starts (docs/adr/0002): borde still
# waiting in the database are closed, as a restart drops unstarted borde
# from now on anyway, and new tables start out playing.
class CloseWaitingTables < ActiveRecord::Migration[8.1]
  def up
    execute "UPDATE tables SET status = 'closed' WHERE status = 'waiting'"
    change_column_default :tables, :status, from: "waiting", to: "playing"
  end

  def down
    change_column_default :tables, :status, from: "playing", to: "waiting"
  end
end
