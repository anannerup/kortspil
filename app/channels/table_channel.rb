# Live play at one table. Each user streams only their own messages, so a
# client never receives another seat's hand. Incoming intents become table
# commands; the results are broadcast per user.
class TableChannel < ApplicationCable::Channel
  def self.stream_name(table_id, user_id) = "table:#{table_id}:user:#{user_id}"

  def self.deliver(outcome)
    outcome.messages.each do |message|
      ActionCable.server.broadcast(stream_name(outcome.table.id, message.user_id), message.payload)
    end
  end

  def subscribed
    table = Table.find_by(id: params[:table_id])
    return reject unless table&.seated?(current_user)

    stream_from self.class.stream_name(table.id, current_user.id)
    TableCommands.new.connect(table:, user: current_user).messages.each { |message| transmit(message.payload) }
  end

  def play(data)
    table = Table.find(params[:table_id])
    self.class.deliver(TableCommands.new.play(table:, user: current_user, card: data["card"]))
  end
end
