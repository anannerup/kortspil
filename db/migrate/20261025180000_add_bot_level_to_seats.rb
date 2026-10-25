# The bot in a seat keeps its level (Hjerterfri::Bot::LEVELS) with it:
# Mellem unless chosen otherwise, Let for a bot that took over from a player
# who forlod. Bots already seated played Mellem.
class AddBotLevelToSeats < ActiveRecord::Migration[8.1]
  def up
    add_column :seats, :bot_level, :string
    execute "UPDATE seats SET bot_level = 'mellem' WHERE bot_name IS NOT NULL"
    add_check_constraint :seats, "(bot_name IS NULL) = (bot_level IS NULL)", name: "seats_bot_level_with_bot"
  end

  def down
    remove_check_constraint :seats, name: "seats_bot_level_with_bot"
    remove_column :seats, :bot_level
  end
end
