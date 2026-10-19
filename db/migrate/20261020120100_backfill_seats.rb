# Seats for the borde that existed before the seats table: each bord's
# latest spil's start snapshot (games.seats), with its seat_log takeovers
# applied. Closed borde are included so their players are still recognised
# (a closed bord sends its player back to the lobby instead of a 404).
class BackfillSeats < ActiveRecord::Migration[8.1]
  class SeatRow < ActiveRecord::Base
    self.table_name = "seats"
  end

  def up
    latest_games = select_rows(<<~SQL)
      SELECT table_id, seats, seat_log FROM games
      WHERE id IN (SELECT MAX(id) FROM games GROUP BY table_id)
    SQL
    rows = latest_games.flat_map { |table_id, seats, seat_log| seat_rows(table_id, JSON.parse(seats), JSON.parse(seat_log)) }
    SeatRow.insert_all(rows) if rows.any?
  end

  def down
    SeatRow.delete_all
  end

  private

  def seat_rows(table_id, seats, seat_log)
    now = Time.current
    occupants = seats.map { |seat| seat["kind"] == "bot" ? [ nil, seat["name"] ] : [ seat["user_id"], nil ] }
    seat_log.each { |entry| occupants[entry["seat"]] = [ nil, entry["to"] ] }
    occupants.each_with_index.map do |(user_id, bot_name), position|
      { table_id:, position:, user_id:, bot_name:, created_at: now, updated_at: now }
    end
  end
end
