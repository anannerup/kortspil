# Presence per seat (heartbeats, frakoblet) and the clock of the current
# wait per spil, for the turn timer and keep-alive (tickets 18 and 19).
class AddPresenceAndTurnClock < ActiveRecord::Migration[8.1]
  def change
    change_table :seats, bulk: true do |t|
      t.datetime :heartbeat_at
      t.datetime :connected_at
      t.datetime :disconnected_at
      t.datetime :warned_at
    end
    change_table :games, bulk: true do |t|
      t.datetime :turn_started_at
      t.datetime :tick_at
    end
  end
end
