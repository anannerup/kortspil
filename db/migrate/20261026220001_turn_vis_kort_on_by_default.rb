# "Vis kort" is on by default: an admin alone with bots sees their hands
# without first switching it on (Anders, 26 October 2026). Only an admin
# alone with bots ever gets it (Game::VisKort), so the default is harmless
# for every other seat.
class TurnVisKortOnByDefault < ActiveRecord::Migration[8.1]
  def change
    change_column_default :seats, :vis_kort, from: false, to: true
  end
end
