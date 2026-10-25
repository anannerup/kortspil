# Live play at one table. Each user streams only their own messages, so a
# client never receives another seat's hand. Incoming intents become the
# bord's actions (Table); their outcomes are broadcast per user. The table chat goes the
# same way, so only the seated hear it, before and during a spil.
#
# Before the start the bord is a WaitingTable (subscribed with
# `waiting_table_id`): only the chat goes this way then (its spil actions
# do nothing yet).
#
# Presence (ticket 18): subscribing is connecting, the client's
# "heartbeat" every few seconds keeps the seat connected, and the
# subscription closing makes it frakoblet (Table#disconnect). A
# half-open connection stops heartbeating, which the clock notices.
class TableChannel < ApplicationCable::Channel
  def self.stream_name(table_id, user_id) = "table:#{table_id}:user:#{user_id}"

  def self.deliver(outcome)
    outcome.messages.each do |message|
      ActionCable.server.broadcast(stream_name(outcome.table.id, message.user_id), message.payload)
    end
  end

  def subscribed
    table = self.table
    return reject unless table&.open_to?(current_user)

    stream_from self.class.stream_name(table.id, current_user.id)
    table.chat_history(user: current_user).messages.each { |message| transmit(message.payload) }
    outcome = table.connect(user: current_user)
    own, others = outcome.messages.partition { |message| message.user_id == current_user.id }
    own.each { |message| transmit(message.payload) }
    self.class.deliver(outcome.with(messages: others))
  end

  def unsubscribed
    with_table { |table| self.class.deliver(table.disconnect(user: current_user)) }
  end

  def heartbeat(_data)
    with_table { |table| self.class.deliver(table.heartbeat(user: current_user)) }
  end

  def pass(data)
    with_table { |table| self.class.deliver(table.pass(player: current_user, cards: data["cards"])) }
  end

  def play(data)
    with_table { |table| self.class.deliver(table.play(player: current_user, card: data["card"])) }
  end

  def choose_moon(data)
    with_table { |table| self.class.deliver(table.choose_moon(player: current_user, option: data["option"])) }
  end

  def next_runde(_data)
    with_table { |table| self.class.deliver(table.deal_next_runde(user: current_user)) }
  end

  def play_again(_data)
    with_table { |table| self.class.deliver(table.play_again(user: current_user)) }
  end

  def chat(data)
    with_table { |table| self.class.deliver(table.chat(user: current_user, text: data["text"])) }
  end

  protected

  # The bord as it is now: waiting (in memory) or stored. Nil once gone.
  def table
    return WaitingTables.default.find(params[:waiting_table_id]) if params[:waiting_table_id]

    Table.find_by(id: params[:table_id])
  end

  private

  def with_table
    current = table
    yield current if current
  end
end
