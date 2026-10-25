require "test_helper"

class TableChannelTest < ActionCable::Channel::TestCase
  setup do
    @user = users(:approved)
    @table = started_practice(@user)
    @stream = TableChannel.stream_name(@table.id, @user.id)
    TableChat.default.forget(@table.id)
  end

  test "a seated user subscribes to their own stream and gets the state" do
    stub_connection current_user: @user

    subscribe table_id: @table.id

    assert subscription.confirmed?
    assert_has_stream @stream
    assert_equal "state", transmissions.last["type"]
    assert_equal "passing", transmissions.last["state"]["view"]["phase"]
  end

  test "a pass is answered on the user's stream and stored" do
    stub_connection current_user: @user
    subscribe table_id: @table.id
    cards = transmissions.last["state"]["view"]["hand"].last(3)

    assert_broadcasts(@stream, 1) { perform :pass, cards: }

    assert_equal cards.sort, @table.current_game.current_round.reload.passes.split.first(3).sort
  end

  test "a play during the pass is rejected on the user's stream" do
    stub_connection current_user: @user
    subscribe table_id: @table.id

    assert_broadcast_on(@stream, { "type" => "rejected", "reason" => "passing_not_complete", "card" => "AH" }) do
      perform :play, card: "AH"
    end
  end

  test "next runde does nothing while the runde is in progress" do
    stub_connection current_user: @user
    subscribe table_id: @table.id

    assert_no_broadcasts(@stream) do
      perform :next_runde
    end
  end

  test "a heartbeat keeps the seat heard from" do
    stub_connection current_user: @user
    subscribe table_id: @table.id

    travel 5.seconds do
      perform :heartbeat
      assert_in_delta Time.current, Seat.find_by(table: @table, user: @user).heartbeat_at, 1
    end
  end

  test "closing the subscription in a spil in progress at an open table makes the seat frakoblet and tells the others" do
    players = [ users(:approved), users(:admin), users(:erik), users(:frida) ]
    surroundings = Table::Surroundings.new(scheduler: FakeScheduler.new)
    @table.leave(user: @user, surroundings:)
    table = WaitingTable.set_up(user: players.first, surroundings:).table
    players.drop(1).each.with_index(1) { |player, seat| table.sit(user: player, seat:, surroundings:) }
    table = table.start(user: players.first, surroundings:).table
    stub_connection current_user: users(:erik)
    subscribe table_id: table.id

    assert_broadcasts(TableChannel.stream_name(table.id, players.first.id), 1) { unsubscribe }

    assert table.seating.occupants[2].frakoblet?
  end

  test "at an es-makker table the bidding goes through the channel, and every seat gets its state" do
    players = [ users(:approved), users(:admin), users(:erik), users(:frida) ]
    table = started_esmakker(players)
    stub_connection current_user: players[1]
    subscribe table_id: table.id
    assert_equal [ 1, true ], transmissions.last["state"]["view"].then { |view| [ view["to_act"], view["choices"]["pas"] ] }

    streams = players.map { |player| TableChannel.stream_name(table.id, player.id) }

    assert_broadcasts(streams[0], 1) { assert_broadcasts(streams[1], 1) { assert_broadcasts(streams[3], 1) { perform :bid, melding: "9" } } }
    assert_equal "1:9", table.current_game.current_round.reload.actions
    # Not this seat's turn any more: answered to it only.
    assert_no_broadcasts(streams[2]) { assert_broadcasts(streams[1], 1) { perform :pas } }
  end

  test "an es-makker intent out of turn is rejected on the user's own stream" do
    players = [ users(:approved), users(:admin), users(:erik), users(:frida) ]
    table = started_esmakker(players)
    stub_connection current_user: players[2]
    subscribe table_id: table.id
    stream = TableChannel.stream_name(table.id, players[2].id)

    assert_broadcast_on(stream, { "type" => "rejected", "reason" => "not_your_turn", "melding" => "10halve" }) { perform :bid, melding: "10halve" }
    assert_broadcast_on(stream, { "type" => "rejected", "reason" => "not_your_turn" }) { perform :det_kan_jeg_selv }
    assert_broadcast_on(stream, { "type" => "rejected", "reason" => "not_your_turn" }) { perform :gaa_med }
    assert_broadcast_on(stream, { "type" => "rejected", "reason" => "no_jernhaand" }) { perform :claim_jernhaand }
  end

  test "at an es-makker table the melder's trump, ace, kitty and the stik go through the channel" do
    players = [ users(:approved), users(:admin), users(:erik), users(:frida) ]
    table = started_esmakker(players)
    surroundings = Table::Surroundings.new(scheduler: FakeScheduler.new)
    table.bid(player: players[1], melding: "8", surroundings:)
    players.values_at(2, 3, 0).each { |player| table.pas(player:, surroundings:) }
    stub_connection current_user: players[1]
    subscribe table_id: table.id
    stream = TableChannel.stream_name(table.id, players[1].id)

    assert_broadcast_on(stream, { "type" => "rejected", "reason" => "unknown_trump", "trump" => nil }) { perform :choose_trump, trump: "spar" }
    perform :choose_trump, trump: "trumfloes"
    ace = table.current_game.reload.engine_round.view_for(1)[:choices][:aces].first
    perform :call_ace, suit: ace
    kitty = table.current_game.reload.engine_round.deal.kitty.map(&:to_s)
    assert_broadcast_on(stream, { "type" => "rejected", "reason" => "wrong_card_count", "cards" => kitty.first(2) }) { perform :discard, cards: kitty.first(2) }
    perform :discard, cards: kitty
    card = table.current_game.reload.engine_round.view_for(1)[:play][:legal_moves].first
    streams = players.map { |player| TableChannel.stream_name(table.id, player.id) }
    assert_broadcasts(streams[2], 1) { perform :play, card: }

    assert_equal "1:8 2:pas 3:pas 0:pas 1:trumftrumfloes 1:es#{ace} 1:kast-#{kitty.join('-')} 1:#{card}", table.current_game.current_round.reload.actions
  end

  test "a user who does not sit at the table is rejected" do
    stub_connection current_user: users(:admin)

    subscribe table_id: @table.id

    assert subscription.rejected?
  end

  test "a closed table rejects the subscription" do
    @table.leave(user: @user)
    stub_connection current_user: @user

    subscribe table_id: @table.id

    assert subscription.rejected?
  end

  test "chat is posted on the stream and replayed on subscribing again" do
    stub_connection current_user: @user
    subscribe table_id: @table.id
    assert_equal({ "type" => "chat_history", "messages" => [], "max_length" => TableChat::MAX_LENGTH }, transmissions.first)

    assert_broadcasts(@stream, 1) { perform :chat, text: "Hej bots" }

    unsubscribe
    subscribe table_id: @table.id
    assert_equal [ "Hej bots" ], transmissions.find { |message| message["type"] == "chat_history" && message["messages"].any? }["messages"].map { |message| message["text"] }
  end

  test "at a table that has not started a seated user gets only the chat" do
    table = WaitingTable.set_up(user: users(:erik)).table
    TableChat.default.forget(table.id)
    stub_connection current_user: users(:erik)

    subscribe waiting_table_id: table.id

    assert subscription.confirmed?
    assert_equal [ "chat_history" ], transmissions.map { |message| message["type"] }
  end

  private

  def started_esmakker(players)
    surroundings = Table::Surroundings.new(scheduler: FakeScheduler.new)
    @table.leave(user: @user, surroundings:)
    table = WaitingTable.set_up(user: players.first, game: "esmakker", surroundings:).table
    players.drop(1).each.with_index(1) { |player, seat| table.sit(user: player, seat:, surroundings:) }
    table.start(user: players.first, surroundings:).table
  end
end
