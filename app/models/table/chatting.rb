class Table
  # The table chat (TableChat, in memory), open to the humans seated at the
  # bord, before and during a spil: #chat posts, #chat_history replays. The
  # same at a waiting bord (WaitingTable) as at a stored one; it needs the
  # bord's #seating, #closed? and #id, and #afresh: the bord as it is now.
  module Chatting
    # A seated user says something to the table. Every human seated there
    # gets the message; a refused one (blank, too long, too fast) is
    # answered to the author only. Nobody else may post.
    def chat(user:, text:, surroundings: Surroundings.new)
      table = afresh(surroundings)
      seating = table.seating
      seat = seating.seat_of(user)
      return Outcome.new(table:) if seat.nil? || table.closed?

      posted = surroundings.chat.post(table.id, author: seating.occupants.fetch(seat), text:)
      if posted.refused?
        return Outcome.new(table:, messages: [ Message.new(seat:, user_id: user.id, payload: { "type" => "chat_rejected", "reason" => posted.refusal.to_s }) ])
      end

      payload = { "type" => "chat_message", "message" => posted.entry.as_json }
      humans = seating.occupants.select(&:human?)
      Outcome.new(table:, messages: humans.map { |human| Message.new(seat: human.seat, user_id: human.user_id, payload:) })
    end

    # The table's recent chat for a seated user who (re)opens the table.
    def chat_history(user:, surroundings: Surroundings.new)
      table = afresh(surroundings)
      seat = table.seating.seat_of(user)
      return Outcome.new(table:) if seat.nil? || table.closed?

      payload = { "type" => "chat_history", "messages" => surroundings.chat.messages(table.id).map(&:as_json), "max_length" => TableChat::MAX_LENGTH }
      Outcome.new(table:, messages: [ Message.new(seat:, user_id: user.id, payload:) ])
    end

    private

    # A stored bord reads its seats fresh anyway.
    def afresh(_surroundings) = self
  end
end
