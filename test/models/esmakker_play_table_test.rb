require "test_helper"

# Seam 2 for ticket 03: an ordinary melding played through the bord's
# actions (choose_trump, call_ace, discard, play), each answered with every
# seat's state; the runde result, the next runde, and a short spil that
# ends after the bord's number of runder.
#
# Seats: the vært (seat 0) deals runde 1, so erik (seat 1) is forhånd,
# then frida (2) and admin (3).
class EsmakkerPlayTableTest < ActiveSupport::TestCase
  setup do
    @host = users(:approved)
    @players = [ @host, users(:erik), users(:frida), users(:admin) ]
    @scheduler = FakeScheduler.new
    @clock = FakeClock.new
  end

  test "a whole ordinary runde: trump, the called ace, the kitty, 13 stik and the result, every seat told" do
    table = started_table
    host, erik, frida, admin = @players
    win_bidding(table, erik, "8")

    assert_rejected :not_your_turn, player_acts(table, :choose_trump, player: frida, trump: "H", surroundings:), frida
    assert_rejected :unknown_trump, player_acts(table, :choose_trump, player: erik, trump: "Z", surroundings:), erik
    outcome = player_acts(table, :choose_trump, player: erik, trump: "H", surroundings:)
    assert_equal "H", state_of(outcome, admin)["view"]["play"]["trump"]

    aces = view_of(outcome, erik)["choices"]["aces"]
    held = Esmakker::Card::SUITS - aces
    assert_rejected :own_ace, player_acts(table, :call_ace, player: erik, suit: held.first, surroundings:), erik if held.any?
    outcome = player_acts(table, :call_ace, player: erik, suit: aces.first, surroundings:)
    melder = view_of(outcome, erik)
    assert_equal [ "discarding", 16, 3 ], [ melder["phase"], melder["hand"].size, melder["play"]["kitty_cards"].size ]
    assert_equal [ 16, 0 ], [ view_of(outcome, host)["card_counts"]["1"], view_of(outcome, host)["kitty_count"] ]

    assert_rejected :wrong_card_count, player_acts(table, :discard, player: erik, cards: melder["hand"].first(2), surroundings:), erik
    laid = melder["hand"].first(3)
    outcome = player_acts(table, :discard, player: erik, cards: laid, surroundings:)
    assert_equal laid.sort, view_of(outcome, erik)["play"]["discarded"].sort
    [ host, frida, admin ].each { |player| assert_empty laid & cards_in(message_for(outcome, player).payload), "#{player.username} never sees the cards laid away" }
    assert_equal [ 1, "playing" ], view_of(outcome, frida).values_at("to_act", "phase")

    outcome = play_out(table)

    @players.each do |player|
      view = view_of(outcome, player)
      assert_equal [ "complete", "played", 1, 13 ], [ view["phase"], view["result"]["kind"], view["result"]["melder"], view["result"]["tricks_won"].sum ]
      assert_equal view["result"]["stik"] >= 8, view["result"]["gik_hjem"]
    end
    game = table.current_game
    assert_equal [ { game_id: game.id, number: 2, delay: Table::Playing::RESULT_PAUSE } ], @scheduler.deals
    assert_equal 1, state_of(outcome, frida)["score"]["results"].size

    dealt = table.next_runde(game_id: game.id, number: 2, surroundings:)
    state = state_of(dealt, admin)
    assert_equal [ 2, 2, 1, 2, "bidding" ], [ state["runde"], state["round_number"], state["view"]["dealer"], state["view"]["to_act"], state["view"]["phase"] ]
  end

  test "no seat ever sees another seat's cards, the kitty, or who the esmakker is before the ace falls" do
    table = started_table
    _host, erik, = @players
    win_bidding(table, erik, "9")
    player_acts(table, :choose_trump, player: erik, trump: "trumfloes", surroundings:)
    outcome = player_acts(table, :call_ace, player: erik, suit: engine_view(table, 1)[:choices][:aces].first, surroundings:)
    melder_hand = view_of(outcome, erik)["hand"]
    outcome = player_acts(table, :discard, player: erik, cards: melder_hand.last(3), surroundings:)

    loop do
      game = Game.find(table.current_game.id)
      round = game.engine_round
      outcome.messages.each do |message|
        seat = message.seat
        own = round.view_for(seat)[:hand]
        visible = cards_in(message.payload) - own - round.view_for(seat)[:play][:discarded] - round.play.trick.cards.map(&:to_s) - round.play.tricks.flat_map(&:cards).map(&:to_s)
        assert_empty visible, "seat #{seat} sees only its own cards and those played"
        known = message.payload["state"]["view"]["play"]["esmakker"]
        assert_nil known unless round.play.esmakker_known?(seat)
      end
      break if round.complete?

      outcome = play_legal(table, round.to_act)
    end
  end

  test "a short spil: the spil ends after the bord's runder with every runde's result" do
    table = started_table(runder: 2)
    host, erik, frida, admin = @players

    win_bidding(table, erik, "bordlaegger")
    keep_kitty(table)
    play_out(table)
    game = table.current_game
    outcome = table.next_runde(game_id: game.id, number: 2, surroundings:)
    assert_equal [ 2, 2 ], state_of(outcome, host).values_at("runde", "runder")

    # Runde 2: erik deals, so frida is forhånd.
    player_acts(table, :bid, player: frida, melding: "8", surroundings:)
    [ admin, host, erik ].each { |player| player_acts(table, :pas, player:, surroundings:) }
    player_acts(table, :choose_trump, player: frida, trump: "S", surroundings:)
    outcome = player_acts(table, :call_ace, player: frida, suit: engine_view(table, 2)[:choices][:aces].first, surroundings:)
    player_acts(table, :discard, player: frida, cards: view_of(outcome, frida)["play"]["kitty_cards"], surroundings:)
    outcome = play_out(table)

    assert Game.find(game.id).finished?
    assert Table.find(table.id).closed?
    state = state_of(outcome, admin)
    assert state["next_path"].present?, "the spil ends the bord's way: on to a new waiting bord"
    assert_equal [ "finished", 2 ], [ state["status"], state["runde"] ]
    assert_equal [ %w[sol bordlaegger 1], %w[played 8 2] ], state["score"]["results"].map { |result| result.values_at("kind", "melding", "melder").map(&:to_s) }
  end

  test "a player who forlader during the play: the bot in the seat plays on, so the runde finishes" do
    table = started_table
    _host, erik, frida, = @players
    win_bidding(table, erik, "8")
    player_acts(table, :choose_trump, player: erik, trump: "C", surroundings:)

    table.leave(user: erik, surroundings:)
    game = Game.find(table.current_game.id)
    assert game.seating.occupants.fetch(1).bot?
    turn = @scheduler.turns.last
    Table::BotPlayer.wake(**turn, surroundings:)
    Table::BotPlayer.wake(**@scheduler.turns.last, surroundings:)
    assert_equal :playing, Game.find(game.id).engine_round.phase, "the bot called an ace and laid the kitty back"

    play_out(table)

    round = Game.find(game.id).engine_round
    assert_equal [ :complete, 1 ], [ round.phase, round.result.melder ]
    assert_equal frida.id, Table.find(table.id).seating.occupants.fetch(2).user_id
  end

  private

  def surroundings(seed: 0) = Table::Surroundings.new(clock: @clock, scheduler: @scheduler, shuffler: Random.new(seed), random: Random.new(seed))

  # The stored es-makker bord with its spil started (`runder` runder).
  def started_table(runder: nil)
    waiting = WaitingTable.set_up(user: @host, game: "esmakker", surroundings:).table
    @players.drop(1).each_with_index { |user, index| waiting.sit(user:, seat: index + 1, surroundings:) }
    table = waiting.reload.start(user: @host, surroundings:).table
    # The settings allow 5–50 runder; a short spil is set on the row.
    table.update_column(:runder, runder) if runder
    Table.find(table.id)
  end

  # `player` (the forhånd) bids `melding`, the other three pass.
  def win_bidding(table, player, melding)
    seat = table.seating.seat_of(player)
    outcome = player_acts(table, :bid, player:, melding:, surroundings:)
    3.times { |offset| outcome = player_acts(table, :pas, player: user_at(table, (seat + 1 + offset) % 4), surroundings:) }
    outcome
  end

  def user_at(table, seat) = User.find(table.seating.occupants.fetch(seat).user_id)

  # What the seat sees now (the engine's view of the stored runde).
  def engine_view(table, seat) = Game.find(table.current_game.id).engine_round.view_for(seat)

  # At a sol-melding each seat in turn lays the kitty back (keeps its hand).
  def keep_kitty(table)
    loop do
      round = Game.find(table.current_game.id).engine_round
      return unless round.phase == :exchanging

      player_acts(table, :discard, player: user_at(table, round.to_act), cards: round.view_for(round.to_act)[:play][:kitty_cards], surroundings:)
    end
  end

  # Each seat to act plays its first legal card until the runde is complete.
  def play_out(table)
    outcome = nil
    loop do
      round = Game.find(table.current_game.id).engine_round
      return outcome if round.complete?

      outcome = play_legal(table, round.to_act)
    end
  end

  # The seat plays its first legal card; a bot in the seat is woken to
  # take its turn.
  def play_legal(table, seat)
    game = Game.find(table.current_game.id)
    occupant = game.seating.occupants.fetch(seat)
    return Table::BotPlayer.wake(game_id: game.id, seat:, version: game.version, surroundings:) if occupant.bot?

    player_acts(table, :play, player: User.find(occupant.user_id), card: engine_view(table, seat)[:play][:legal_moves].first, surroundings:)
  end

  def message_for(outcome, user) = outcome.messages.find { |message| message.user_id == user.id }
  def state_of(outcome, user) = message_for(outcome, user).payload["state"]
  def view_of(outcome, user) = state_of(outcome, user)["view"]
  def cards_in(payload) = payload.to_json.scan(/"([2-9TJQKA][CDHS]|X\d)"/).flatten.uniq

  def assert_rejected(reason, outcome, user)
    message = outcome.messages.sole
    assert_equal [ "rejected", reason.to_s, user.id ], [ message.payload["type"], message.payload["reason"], message.user_id ]
  end
end
