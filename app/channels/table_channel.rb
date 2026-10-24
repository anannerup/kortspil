# Live play at one table. Each user streams only their own messages, so a
# client never receives another seat's hand. Incoming intents become table
# commands; the results are broadcast per user.
#
# Presence (ticket 18): subscribing is connecting, the client's
# "heartbeat" every few seconds keeps the seat connected, and the
# subscription closing makes it frakoblet (TableCommands#disconnect). A
# half-open connection stops heartbeating, which the clock notices.
class TableChannel < ApplicationCable::Channel
  def self.stream_name(table_id, user_id) = "table:#{table_id}:user:#{user_id}"

  def self.deliver(outcome)
    outcome.messages.each do |message|
      ActionCable.server.broadcast(stream_name(outcome.table.id, message.user_id), message.payload)
    end
  end

  def subscribed
    table = Table.find_by(id: params[:table_id])
    return reject unless table&.open_to?(current_user)

    stream_from self.class.stream_name(table.id, current_user.id)
    outcome = TableCommands.new.connect(table:, user: current_user)
    own, others = outcome.messages.partition { |message| message.user_id == current_user.id }
    own.each { |message| transmit(message.payload) }
    self.class.deliver(outcome.with(messages: others))
  end

  def unsubscribed
    table = Table.find_by(id: params[:table_id])
    self.class.deliver(TableCommands.new.disconnect(table:, user: current_user)) if table
  end

  def heartbeat(_data)
    self.class.deliver(TableCommands.new.heartbeat(table:, user: current_user))
  end

  def pass(data)
    self.class.deliver(TableCommands.new.pass(table:, user: current_user, cards: data["cards"]))
  end

  def play(data)
    self.class.deliver(TableCommands.new.play(table:, user: current_user, card: data["card"]))
  end

  def choose_moon(data)
    self.class.deliver(TableCommands.new.choose_moon(table:, user: current_user, option: data["option"]))
  end

  def next_runde(_data)
    self.class.deliver(TableCommands.new.deal_next_runde(table:, user: current_user))
  end

  def play_again(_data)
    self.class.deliver(TableCommands.new.play_again(table:, user: current_user))
  end

  private

  def table = Table.find(params[:table_id])
end
