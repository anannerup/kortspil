require "test_helper"

# Seam 2, the table chat (ticket 17): driven through TableCommands#chat and
# #chat_history with an in-memory TableChat and a fake clock.
class TableCommandsChatTest < ActiveSupport::TestCase
  Clock = Struct.new(:now)

  setup do
    @host = users(:approved)
    @erik = users(:erik)
    @clock = Clock.new(Time.utc(2026, 10, 25, 19, 30))
    @chat = TableChat.new(clock: @clock)
    @commands = TableCommands.new(scheduler: FakeScheduler.new, chat: @chat)
    @table = @commands.create_table(user: @host).table
    @commands.sit(table: @table, user: @erik, seat: 2)
  end

  test "a message goes to every human seated at the table, with author and time" do
    outcome = @commands.chat(table: @table, user: @erik, text: "  Hej   med jer  ")

    assert_equal [ @host.id, @erik.id ].sort, outcome.messages.map(&:user_id).sort
    payloads = outcome.messages.map(&:payload).uniq
    assert_equal [ { "type" => "chat_message",
                     "message" => { "id" => payloads.sole["message"]["id"], "user_id" => @erik.id, "seat" => 2, "name" => @erik.username,
                                    "text" => "Hej med jer", "at" => "2026-10-25T19:30:00Z" } } ], payloads
  end

  test "history replays the last 50 messages, oldest first, to a seated user" do
    55.times do |index|
      @clock.now += TableChat::FLOOD_WINDOW
      @commands.chat(table: @table, user: index.even? ? @host : @erik, text: "besked #{index}")
    end

    history = @commands.chat_history(table: @table, user: @erik).messages.sole
    assert_equal @erik.id, history.user_id
    assert_equal "chat_history", history.payload["type"]
    assert_equal TableChat::MAX_LENGTH, history.payload["max_length"]
    assert_equal (5...55).map { |index| "besked #{index}" }, history.payload["messages"].map { |message| message["text"] }
  end

  test "history survives the spil starting, and players can chat during it" do
    @commands.chat(table: @table, user: @host, text: "Velkommen")
    @commands.sit(table: @table, user: users(:admin), seat: 1)
    @commands.sit(table: @table, user: users(:frida), seat: 3)
    @table = @commands.start(table: @table, user: @host).table

    assert_equal 4, @commands.chat(table: @table, user: users(:frida), text: "Held og lykke").messages.size
    texts = @commands.chat_history(table: @table, user: @erik).messages.sole.payload["messages"].map { |message| message["text"] }
    assert_equal [ "Velkommen", "Held og lykke" ], texts
  end

  test "only seated players may post or read" do
    outsider = users(:admin)

    assert_empty @commands.chat(table: @table, user: outsider, text: "Må jeg være med?").messages
    assert_empty @commands.chat_history(table: @table, user: outsider).messages
    assert_empty @chat.messages(@table.id)
  end

  test "a player who stands up no longer hears the table" do
    @commands.leave(table: @table, user: @erik)

    outcome = @commands.chat(table: @table, user: @host, text: "Hvor blev du af?")

    assert_equal [ @host.id ], outcome.messages.map(&:user_id)
  end

  test "text is kept as plain text, not interpreted" do
    outcome = @commands.chat(table: @table, user: @host, text: "<script>alert(1)</script> & <b>fed</b>")

    assert_equal "<script>alert(1)</script> & <b>fed</b>", outcome.messages.first.payload["message"]["text"]
  end

  test "blank, too long and too fast messages are refused to the author only" do
    assert_chat_rejected "blank", @commands.chat(table: @table, user: @host, text: " \n\t ")
    assert_chat_rejected "too_long", @commands.chat(table: @table, user: @host, text: "a" * (TableChat::MAX_LENGTH + 1))
    assert_equal 2, @commands.chat(table: @table, user: @host, text: "a" * TableChat::MAX_LENGTH).messages.size

    (TableChat::FLOOD_COUNT - 1).times { |index| @commands.chat(table: @table, user: @host, text: "nr. #{index}") }
    assert_chat_rejected "too_fast", @commands.chat(table: @table, user: @host, text: "en til")
    assert_equal 2, @commands.chat(table: @table, user: @erik, text: "Ro på").messages.size, "the flood guard is per player"

    @clock.now += TableChat::FLOOD_WINDOW
    assert_equal 2, @commands.chat(table: @table, user: @host, text: "en til").messages.size
  end

  test "a closed table has no chat" do
    table = started
    frida = users(:frida)
    @commands.chat(table:, user: frida, text: "Farvel")
    table.closed!

    assert_empty @commands.chat(table:, user: frida, text: "Hallo?").messages
    assert_empty @commands.chat_history(table:, user: frida).messages
  end

  test "closing a bord forgets its chat in the shared log, before and after the start" do
    commands = TableCommands.new(scheduler: FakeScheduler.new)
    commands.chat(table: @table, user: @host, text: "Hej")
    assert_equal 1, TableChat.default.messages(@table.id).size

    commands.leave(table: @table, user: @erik)
    commands.leave(table: @table, user: @host)
    assert_empty TableChat.default.messages(@table.id)

    table = started(commands)
    commands.chat(table:, user: users(:frida), text: "Hej")
    table.closed!
    assert_empty TableChat.default.messages(table.id)
  end

  private

  # A stored table: Frida's new bord with three bots, started.
  def started(commands = @commands)
    frida = users(:frida)
    waiting = commands.create_table(user: frida).table
    1.upto(3) { |seat| commands.add_bot(table: waiting, user: frida, seat:) }
    commands.start(table: waiting, user: frida).table
  end

  def assert_chat_rejected(reason, outcome)
    assert_equal [ [ @host.id, { "type" => "chat_rejected", "reason" => reason } ] ], outcome.messages.map { |message| [ message.user_id, message.payload ] }
  end
end
