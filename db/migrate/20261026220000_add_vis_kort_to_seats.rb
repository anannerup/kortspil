# "Vis kort" (esmakker-bots ticket 02): whether the admin in a seat has it
# on for this spil, and each bot seat's latest thought (what it intended
# with its last decision), written only while someone at the bord has it on.
class AddVisKortToSeats < ActiveRecord::Migration[8.1]
  def change
    add_column :seats, :vis_kort, :boolean, default: false, null: false
    add_column :seats, :bot_thought, :json
  end
end
