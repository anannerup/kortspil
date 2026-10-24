# Live play at one table. Each user streams only their own messages, so a
# client never receives another seat's hand. Incoming intents become table
# commands; the results are broadcast per user. The table chat goes the
# same way, so only the seated hear it, before and during a spil.
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
    TableCommands.new.chat_history(table:, user: current_user).messages.each { |message| transmit(message.payload) }
    TableCommands.new.connect(table:, user: current_user).messages.each { |message| transmit(message.payload) }
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

  def chat(data)
    self.class.deliver(TableCommands.new.chat(table:, user: current_user, text: data["text"]))
  end

  private

  def table = Table.find(params[:table_id])
end
