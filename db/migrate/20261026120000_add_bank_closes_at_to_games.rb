# When an es-makker spil's bank window closes (ticket 08): set when vip's
# trump is named, cleared when the window closes. The countdown and the
# bord's refusal of a late bank read it.
class AddBankClosesAtToGames < ActiveRecord::Migration[8.1]
  def change
    add_column :games, :bank_closes_at, :datetime
  end
end
