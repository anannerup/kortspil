require "test_helper"

# Seam 2, the table chat (ticket 17): driven through the bord's #chat and
# #chat_history (Table::Chatting) with an in-memory TableChat and a fake clock.
class TableChattingTest < ActiveSupport::TestCase
  Clock = Struct.new(:now)

  setup do
    @host = users(:approved)
    @erik = users(:erik)
    @clock = Clock.new(Time.utc(2026, 10, 25, 19, 30))
    @chat = TableChat.new(clock: @clock)
    @surroundings = Table::Surroundings.new(scheduler: FakeScheduler.new, chat: @chat, shuffler: Random.new(0), random: Random.new(0))
    @table = WaitingTable.set_up(user: @host, surroundings: @surroundings).table
    @table.sit(user: @erik, seat: 2, surroundings: @surroundings)
  end

  test "a message goes to every human seated at the table, with author and time" do
    outcome = @table.chat(user: @erik, text: "  Hej   med jer  ", surroundings: @surroundings)

    assert_equal [ @host.id, @erik.id ].sort, outcome.messages.map(&:user_id).sort
    payloads = outcome.messages.map(&:payload).uniq
    assert_equal [ { "type" => "chat_message",
                     "message" => { "id" => payloads.sole["message"]["id"], "user_id" => @erik.id, "seat" => 2, "name" => @erik.username,
                                    "text" => "Hej med jer", "at" => "2026-10-25T19:30:00Z" } } ], payloads
  end

  test "history replays the last 50 messages, oldest first, to a seated user" do
    55.times do |index|
      @clock.now += TableChat::FLOOD_WINDOW
      @table.chat(user: index.even? ? @host : @erik, text: "besked #{index}", surroundings: @surroundings)
    end

    history = @table.chat_history(user: @erik, surroundings: @surroundings).messages.sole
    assert_equal @erik.id, history.user_id
    assert_equal "chat_history", history.payload["type"]
    assert_equal TableChat::MAX_LENGTH, history.payload["max_length"]
    assert_equal (5...55).map { |index| "besked #{index}" }, history.payload["messages"].map { |message| message["text"] }
  end

  test "history survives the spil starting, and players can chat during it" do
    @table.chat(user: @host, text: "Velkommen", surroundings: @surroundings)
    @table.sit(user: users(:admin), seat: 1, surroundings: @surroundings)
    @table.sit(user: users(:frida), seat: 3, surroundings: @surroundings)
    @table = @table.start(user: @host, surroundings: @surroundings).table

    assert_equal 4, @table.chat(user: users(:frida), text: "Held og lykke", surroundings: @surroundings).messages.size
    texts = @table.chat_history(user: @erik, surroundings: @surroundings).messages.sole.payload["messages"].map { |message| message["text"] }
    assert_equal [ "Velkommen", "Held og lykke" ], texts
  end

  test "only seated players may post or read" do
    outsider = users(:admin)

    assert_empty @table.chat(user: outsider, text: "Må jeg være med?", surroundings: @surroundings).messages
    assert_empty @table.chat_history(user: outsider, surroundings: @surroundings).messages
    assert_empty @chat.messages(@table.id)
  end

  test "a player who stands up no longer hears the table" do
    @table.leave(user: @erik, surroundings: @surroundings)

    outcome = @table.chat(user: @host, text: "Hvor blev du af?", surroundings: @surroundings)

    assert_equal [ @host.id ], outcome.messages.map(&:user_id)
  end

  test "text is kept as plain text, not interpreted" do
    outcome = @table.chat(user: @host, text: "<script>alert(1)</script> & <b>fed</b>", surroundings: @surroundings)

    assert_equal "<script>alert(1)</script> & <b>fed</b>", outcome.messages.first.payload["message"]["text"]
  end

  test "blank, too long and too fast messages are refused to the author only" do
    assert_chat_rejected "blank", @table.chat(user: @host, text: " \n\t ", surroundings: @surroundings)
    assert_chat_rejected "too_long", @table.chat(user: @host, text: "a" * (TableChat::MAX_LENGTH + 1), surroundings: @surroundings)
    assert_equal 2, @table.chat(user: @host, text: "a" * TableChat::MAX_LENGTH, surroundings: @surroundings).messages.size

    (TableChat::FLOOD_COUNT - 1).times { |index| @table.chat(user: @host, text: "nr. #{index}", surroundings: @surroundings) }
    assert_chat_rejected "too_fast", @table.chat(user: @host, text: "en til", surroundings: @surroundings)
    assert_equal 2, @table.chat(user: @erik, text: "Ro på", surroundings: @surroundings).messages.size, "the flood guard is per player"

    @clock.now += TableChat::FLOOD_WINDOW
    assert_equal 2, @table.chat(user: @host, text: "en til", surroundings: @surroundings).messages.size
  end

  test "a closed table has no chat" do
    table = started
    frida = users(:frida)
    table.chat(user: frida, text: "Farvel", surroundings: @surroundings)
    table.closed!

    assert_empty table.chat(user: frida, text: "Hallo?", surroundings: @surroundings).messages
    assert_empty table.chat_history(user: frida, surroundings: @surroundings).messages
  end

  test "closing a bord forgets its chat in the shared log, before and after the start" do
    surroundings = Table::Surroundings.new(scheduler: FakeScheduler.new, shuffler: Random.new(0), random: Random.new(0))
    @table.chat(user: @host, text: "Hej", surroundings:)
    assert_equal 1, TableChat.default.messages(@table.id).size

    @table.leave(user: @erik, surroundings:)
    @table.leave(user: @host, surroundings:)
    assert_empty TableChat.default.messages(@table.id)

    table = started(surroundings)
    table.chat(user: users(:frida), text: "Hej", surroundings:)
    table.closed!
    assert_empty TableChat.default.messages(table.id)
  end

  private

  # A stored table: Frida's new bord with three bots, started.
  def started(surroundings = @surroundings)
    frida = users(:frida)
    waiting = WaitingTable.set_up(user: frida, surroundings:).table
    1.upto(3) { |seat| waiting.add_bot(user: frida, seat:, surroundings:) }
    waiting.start(user: frida, surroundings:).table
  end

  def assert_chat_rejected(reason, outcome)
    assert_equal [ [ @host.id, { "type" => "chat_rejected", "reason" => reason } ] ], outcome.messages.map { |message| [ message.user_id, message.payload ] }
  end
end
