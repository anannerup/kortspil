require "test_helper"

# Seam 2 for ticket 07: whole vip runder through the bord's actions
# (call_ace, then turn_card / accept_trump by the melder, discard, play),
# each answered with every seat's state: the kitty's turned cards face up
# for all, the rest hidden from all, trump from the card taken, and the
# points doubled by it.
#
# Seats: the vært (seat 0) deals runde 1, so erik (seat 1) is forhånd,
# then frida (2) and admin (3).
class EsmakkerVipTableTest < ActiveSupport::TestCase
  setup do
    @host = users(:approved)
    @players = [ @host, users(:erik), users(:frida), users(:admin) ]
    @scheduler = FakeScheduler.new
    @clock = FakeClock.new
  end

  test "a whole vip runde: the ace first, two cards turned for all to see, the second taken as trump, ×4" do
    table = started_table
    erik = @players[1]
    win_bidding(table, erik, "8vip")
    kitty = engine_round(table).deal.kitty.map(&:to_s)

    assert_rejected :not_now, player_acts(table, :turn_card, player: erik, surroundings:), erik
    aces = engine_view(table, 1)[:choices][:aces]
    outcome = player_acts(table, :call_ace, player: erik, suit: aces.first, surroundings:)
    @players.each do |player|
      view = view_of(outcome, player)
      assert_equal [ "turning", 1, [], 3 ], [ view["phase"], view["to_act"], view["play"]["turned"], view["kitty_count"] ]
      assert_empty kitty & cards_in(message_for(outcome, player).payload), "#{player.username} sees nothing of the kitty yet"
    end
    assert_equal [ true, false ], view_of(outcome, erik)["choices"].values_at("turn_card", "accept_trump")
    assert_rejected :nothing_turned, player_acts(table, :accept_trump, player: erik, surroundings:), erik
    assert_rejected :not_your_turn, player_acts(table, :turn_card, player: @players[2], surroundings:), @players[2]

    player_acts(table, :turn_card, player: erik, surroundings:)
    outcome = player_acts(table, :turn_card, player: erik, surroundings:)
    @players.each do |player|
      assert_equal kitty.first(2), view_of(outcome, player)["play"]["turned"]
      assert_not_includes cards_in(message_for(outcome, player).payload), kitty.last, "#{player.username} never sees the card not turned"
    end

    outcome = player_acts(table, :accept_trump, player: erik, surroundings:)
    trump = Esmakker::Card.parse(kitty[1]).suit || "trumfloes"
    @players.each { |player| assert_equal [ trump, 2, "discarding" ], view_of(outcome, player).then { |view| [ *view["play"].values_at("trump", "vip_card"), view["phase"] ] } }
    melder = view_of(outcome, erik)
    assert_equal [ "discarding", 13, [], 3 ], [ melder["phase"], melder["hand"].size, melder["play"]["kitty_cards"], melder["kitty_count"] ]
    @players.each do |player|
      assert_not_includes cards_in(message_for(outcome, player).payload), kitty.last, "#{player.username} does not see the card not turned while erik lays away"
    end

    outcome = player_acts(table, :discard, player: erik, cards: melder["hand"].first(2), surroundings:)
    assert_equal [ kitty.first(2).sort, 2 ], view_of(outcome, erik)["play"].values_at("kitty_cards", "exchanged").then { |cards, count| [ cards.sort, count ] }, "two from the top: the turned cards"
    @players.each do |player|
      assert_equal [ "banking", 2 ], [ view_of(outcome, player)["phase"], view_of(outcome, player)["play"]["exchanged"] ], "the bank window opens after the exchange; everybody sees how many"
      assert_not_includes cards_in(message_for(outcome, player).payload), kitty.last, "#{player.username}: the card not taken is out, unseen"
    end
    close_bank_window(table)
    outcome = play_out(table)
    result = view_of(outcome, @host)["result"]
    assert_equal [ "played", "8vip", 2, trump ], result.values_at("kind", "melding", "vip_card", "trump")
    assert_equal expected_points(result, factor: 4 * (trump == "trumfloes" ? 2 : 1)), result["points"]
    assert_equal result["points"], state_of(outcome, @host)["score"]["totals"]
    assert_equal 1, @scheduler.deals.size, "the next runde follows"
  end

  test "the third card is trump in any case: turning it names trump and the melder takes the kitty, ×8" do
    table = started_table(seed: 3)
    erik = @players[1]
    win_bidding(table, erik, "9vip")
    kitty = engine_round(table).deal.kitty.map(&:to_s)
    player_acts(table, :call_ace, player: erik, suit: engine_view(table, 1)[:choices][:aces].last, surroundings:)

    2.times { player_acts(table, :turn_card, player: erik, surroundings:) }
    outcome = player_acts(table, :turn_card, player: erik, surroundings:)
    third = Esmakker::Card.parse(kitty.last)
    trump = third.joker? ? "trumfloes" : third.suit
    @players.each do |player|
      view = view_of(outcome, player)
      assert_equal [ kitty, trump, 3, 3 ], [ view["play"]["turned"], view["play"]["trump"], view["play"]["vip_card"], view["kitty_count"] ]
    end
    assert_equal [ "discarding", false, false ], view_of(outcome, erik).then { |view| [ view["phase"], *view["choices"].values_at("turn_card", "accept_trump") ] }
    assert_rejected :not_now, player_acts(table, :turn_card, player: erik, surroundings:), erik

    player_acts(table, :discard, player: erik, cards: view_of(outcome, erik)["hand"].first(3), surroundings:)
    close_bank_window(table)
    result = view_of(play_out(table), @host)["result"]
    assert_equal [ 3, trump ], result.values_at("vip_card", "trump")
    assert_equal expected_points(result, factor: 8 * (trump == "trumfloes" ? 2 : 1)), result["points"]
  end

  test "a player who forlader at vip: the bot in the seat turns the kitty, takes a card as trump and lays away, so the runde finishes" do
    table = started_table
    erik = @players[1]
    win_bidding(table, erik, "8vip")
    player_acts(table, :call_ace, player: erik, suit: engine_view(table, 1)[:choices][:aces].first, surroundings:)

    table.leave(user: erik, surroundings:)
    Table::BotPlayer.wake(**@scheduler.turns.last, surroundings:) until engine_round(table).banking?
    assert_empty engine_round(table).seats_to_act, "the bot took a card as trump and laid three away; it never banks"
    close_bank_window(table)
    round = engine_round(table)
    vip_card = round.play.vip_card
    assert_equal :playing, round.phase
    assert_includes 1..3, vip_card

    until (round = engine_round(table)).complete?
      if round.to_act == 1
        Table::BotPlayer.wake(**@scheduler.turns.last, surroundings:)
      else
        player_acts(table, :play, player: user_at(table, round.to_act), card: engine_view(table, round.to_act)[:play][:legal_moves].first, surroundings:)
      end
    end
    assert_equal [ vip_card, 8 ], [ round.result.vip_card, round.result.melding.number ]
  end

  private

  # The runde points two against two (a selvmakker with each of the three);
  # clubs as trump doubles once more at vip.
  def expected_points(result, factor:)
    factor *= 2 if result["trump"] == "C"
    number = result["melding"].to_i
    over = result["stik"] - number
    stake = Esmakker::Points.standard.stakes.fetch(number.to_s)
    amount = (over.negative? ? stake * -over : stake + over) * factor
    sign = result["gik_hjem"] ? 1 : -1
    side = [ result["melder"], result["esmakker"] ].compact
    (0..3).map do |seat|
      points = (side.include?(seat) ? sign : -sign) * amount * (result["selvmakker"] && seat == result["melder"] ? 3 : 1)
      points == points.to_i ? points.to_i : points
    end
  end

  # The bank window's time runs out (ticket 08): its job runs.
  def close_bank_window(table)
    @clock.advance(Esmakker::Rules.standard.bank_window)
    table.deadline_passed(**@scheduler.deadlines.last.except(:delay), surroundings:)
  end

  def state_of(outcome, user) = message_for(outcome, user).payload["state"]

  def surroundings(seed: @seed || 0) = Table::Surroundings.new(clock: @clock, scheduler: @scheduler, shuffler: Random.new(seed), random: Random.new(seed))

  # The stored es-makker bord with its spil started, dealt with `seed`.
  def started_table(seed: 0)
    @seed = seed
    waiting = WaitingTable.set_up(user: @host, game: "esmakker", surroundings:).table
    @players.drop(1).each_with_index { |user, index| waiting.sit(user:, seat: index + 1, surroundings:) }
    Table.find(waiting.reload.start(user: @host, surroundings:).table.id)
  end

  # The seat holding the suit's ace, nil when it lies in the kitty.
  def holder(deal, suit) = Esmakker::Seats::ALL.find { |seat| deal.hand(seat).include?(Esmakker::Card.new(rank: "A", suit:)) }

  # An ace in the kitty, when the melder holds not all four (she could not call it otherwise).
  def kitty_ace(deal, melder:)
    aces = deal.kitty.select(&:ace?).map(&:suit)
    aces.find { |suit| holder(deal, suit) != melder }
  end

  # `player` (the forhånd) bids `melding`, the other three pass.
  def win_bidding(table, player, melding)
    seat = table.seating.seat_of(player)
    player_acts(table, :bid, player:, melding:, surroundings:)
    3.times { |offset| player_acts(table, :pas, player: user_at(table, (seat + 1 + offset) % 4), surroundings:) }
  end

  def user_at(table, seat) = User.find(table.seating.occupants.fetch(seat).user_id)
  def seat_of(table, user) = table.seating.seat_of(user)
  def engine_round(table) = Game.find(table.current_game.id).engine_round
  def engine_view(table, seat) = engine_round(table).view_for(seat)

  # Each seat to act plays its first legal card until the runde is complete.
  def play_out(table)
    outcome = nil
    loop do
      round = engine_round(table)
      return outcome if round.complete?

      outcome = player_acts(table, :play, player: user_at(table, round.to_act), card: engine_view(table, round.to_act)[:play][:legal_moves].first, surroundings:)
    end
  end

  def message_for(outcome, user) = outcome.messages.find { |message| message.user_id == user.id }
  def view_of(outcome, user) = message_for(outcome, user).payload["state"]["view"]
  def cards_in(payload) = payload.to_json.scan(/"([2-9TJQKA][CDHS]|X\d)"/).flatten.uniq

  def assert_rejected(reason, outcome, user)
    message = outcome.messages.sole
    assert_equal [ "rejected", reason.to_s, user.id ], [ message.payload["type"], message.payload["reason"], message.user_id ]
  end
end
