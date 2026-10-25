# The lobby: the listed borde (open and password) with their type, vært,
# seats, rules and status: those waiting for their spil (WaitingTable, in
# memory) and those playing (Table). Every subscriber gets the whole list on
# subscribing and again after each change to a bord or its seats
# (WaitingTableBroadcasts, Table#refresh_lobby). The list is the same for
# everyone; it holds no hidden information.
#
# A waiting bord's own page subscribes with its `waiting_table_id` instead
# and follows that one bord, so it works for private borde too, which the
# list never shows. It gets { type: "table", table: entry } on subscribing
# and after each change; once the spil starts the entry is the stored
# table's, so the page can follow it there. A page that subscribes only
# after the start (opened just before it, e.g. by accepting a puf) gets
# the stored table's entry at once and follows too. A practice bord is
# refused, and so is a bord that is gone.
# The page asks for "expire_nudges" when a puf's time is up.
class LobbyChannel < ApplicationCable::Channel
  STREAM = "lobby"

  def self.tables_message
    waiting = WaitingTables.default.listed.map(&:lobby_entry)
    { "type" => "tables", "tables" => waiting + Table.listed.includes(:host).map(&:lobby_entry) }
  end

  def self.broadcast_tables = ActionCable.server.broadcast(STREAM, tables_message)

  def self.waiting_table_stream(id) = "#{STREAM}:waiting:#{id}"

  def self.broadcast_waiting_table(id, entry) = ActionCable.server.broadcast(waiting_table_stream(id), { "type" => "table", "table" => entry })

  def subscribed
    return subscribe_to_lobby unless params[:waiting_table_id]

    # Stream before reading the bord, so a start between the two is heard.
    stream_from self.class.waiting_table_stream(params[:waiting_table_id])
    table = WaitingTables.default.find(params[:waiting_table_id])
    return follow_started_table if table.nil?
    return reject if table.practice?

    transmit({ "type" => "table", "table" => table.lobby_entry })
  end

  def expire_nudges(_data)
    WaitingTables.default.find(params[:waiting_table_id])&.expire_nudges
  end

  private

  def follow_started_table
    stored = WaitingTables.default.started_as(params[:waiting_table_id])&.then { |id| Table.find_by(id:) }
    return reject if stored.nil? || stored.practice?

    transmit({ "type" => "table", "table" => stored.lobby_entry })
  end

  def subscribe_to_lobby
    stream_from STREAM
    transmit self.class.tables_message
  end
end
