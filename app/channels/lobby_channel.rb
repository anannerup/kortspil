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
# table's, so the page can follow it there. A practice bord is refused.
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

    table = WaitingTables.default.find(params[:waiting_table_id])
    return reject if table.nil? || table.practice?

    stream_from self.class.waiting_table_stream(table.id)
    transmit({ "type" => "table", "table" => table.lobby_entry })
  end

  def expire_nudges(_data)
    table = WaitingTables.default.find(params[:waiting_table_id])
    TableCommands.new.expire_nudges(table:) if table
  end

  private

  def subscribe_to_lobby
    stream_from STREAM
    transmit self.class.tables_message
  end
end
