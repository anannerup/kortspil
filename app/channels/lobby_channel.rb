# The lobby: the open tables with their vært, seats, rules and status. Every
# subscriber gets the whole list on subscribing and again after each change
# to a listed table or its seats (Table#refresh_lobby). The list is the same
# for everyone; it holds no hidden information.
class LobbyChannel < ApplicationCable::Channel
  STREAM = "lobby"

  def self.tables_message = { "type" => "tables", "tables" => Table.listed.includes(:host).map(&:lobby_entry) }

  def self.broadcast_tables = ActionCable.server.broadcast(STREAM, tables_message)

  def subscribed
    stream_from STREAM
    transmit self.class.tables_message
  end
end
