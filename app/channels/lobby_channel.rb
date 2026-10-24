# The lobby: the listed tables (open and password) with their type, vært,
# seats, rules and status. Every subscriber gets the whole list on
# subscribing and again after each change to a table or its seats
# (Table#refresh_lobby). The list is the same for everyone; it holds no
# hidden information.
#
# A table's waiting room subscribes with its `table_id` instead and follows
# that one table, so it works for private tables too, which the list never
# shows. It gets { type: "table", table: entry } on subscribing and after
# each change; a practice table is refused.
class LobbyChannel < ApplicationCable::Channel
  STREAM = "lobby"

  def self.tables_message = { "type" => "tables", "tables" => Table.listed.includes(:host).map(&:lobby_entry) }

  def self.broadcast_tables = ActionCable.server.broadcast(STREAM, tables_message)

  def self.table_stream(table) = "#{STREAM}:table:#{table.id}"

  def self.table_message(table) = { "type" => "table", "table" => table.lobby_entry }

  def self.broadcast_table(table) = ActionCable.server.broadcast(table_stream(table), table_message(table))

  def subscribed
    return subscribe_to_lobby unless params[:table_id]

    table = Table.find_by(id: params[:table_id])
    return reject if table.nil? || table.practice?

    stream_from self.class.table_stream(table)
    transmit self.class.table_message(table)
  end

  private

  def subscribe_to_lobby
    stream_from STREAM
    transmit self.class.tables_message
  end
end
