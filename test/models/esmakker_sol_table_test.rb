require "test_helper"

# Seam 2 for ticket 09: a whole sol runde through the bord's actions (bid
# and gaa_med; discard for each seat's turn at the kitty; play), each
# answered with every seat's state, ending in the settlement per sol
# player and the next runde.
#
# Seats: the vært (seat 0) deals runde 1, so erik (seat 1) is forhånd,
# then frida (2) and admin (3).
class EsmakkerSolTableTest < ActiveSupport::TestCase
  setup do
    @host = users(:approved)
    @players = [ @host, users(:erik), users(:frida), users(:admin) ]
    @scheduler = FakeScheduler.new
    @clock = FakeClock.new
  end

  test "a whole sol runde: erik bids sol, frida goes with; the kitty goes round, the forhånd leads, each is settled on her own" do
    table = started_table
    host, erik, frida, admin = @players
    player_acts(table, :bid, player: erik, melding: "sol", surroundings:)
    player_acts(table, :gaa_med, player: frida, surroundings:)
    player_acts(table, :pas, player: admin, surroundings:)
    outcome = player_acts(table, :pas, player: host, surroundings:)

    @players.each do |player|
      view = view_of(outcome, player)
      assert_equal [ "exchanging", 1 ], view.values_at("phase", "to_act")
      assert_equal [ "sol", [ 1, 2 ], [ 1, 2, 3, 0 ], 1 ], view["play"].values_at("kind", "players", "exchange_order", "exchanging")
    end
    kitty = Game.find(table.current_game.id).engine_round.deal.kitty.map(&:to_s)
    assert_equal [ [], 13, true, 3 ], [ view_of(outcome, erik)["play"]["kitty_cards"], view_of(outcome, erik)["hand"].size, view_of(outcome, erik)["choices"]["discard"], view_of(outcome, erik)["play"]["discard_size"] ]
    @players.each { |player| assert_empty kitty & cards_in(message_for(outcome, player).payload), "#{player.username} sees nothing of the kitty before the exchange" }
    assert_rejected :not_now, player_acts(table, :choose_trump, player: erik, trump: "H", surroundings:), erik
    assert_rejected :not_your_turn, player_acts(table, :discard, player: frida, cards: [], surroundings:), frida

    # Erik lays one of his own away and takes the kitty's top card; the other two go on to frida.
    own = view_of(outcome, erik)["hand"].first
    outcome = player_acts(table, :discard, player: erik, cards: [ own ], surroundings:)
    assert_equal [ [ own ], kitty.first(1) ], view_of(outcome, erik)["play"].values_at("discarded", "kitty_cards")
    [ host, frida, admin ].each { |player| assert_empty [ own, kitty.first ] & cards_in(message_for(outcome, player).payload) }
    assert_equal [ 2, 2, [ nil, 1, nil, nil ] ], [ view_of(outcome, frida)["to_act"], view_of(outcome, frida)["play"]["discard_size"], view_of(outcome, admin)["play"]["exchanged"] ]

    outcome = player_acts(table, :discard, player: frida, cards: [], surroundings:)
    outcome = player_acts(table, :discard, player: admin, cards: [], surroundings:)
    outcome = player_acts(table, :discard, player: host, cards: [], surroundings:)
    assert_equal [ "playing", 1 ], view_of(outcome, host).values_at("phase", "to_act"), "the forhånd leads"

    outcome = play_out(table)
    result = view_of(outcome, host)["result"]
    assert_equal [ "sol", [ 1, 2 ], 1 ], [ result["kind"], result["sol"]["players"], result["sol"]["most_stik"] ]
    vaeltet = result["sol"]["vaeltet"]
    # Each pair settles once, the better outcome getting 3 from the other.
    sol_outcome = ->(seat) { [ 1, 2 ].include?(seat) ? (vaeltet.include?(seat) ? -1 : 1) : 0 }
    expected = [ 0, 0, 0, 0 ]
    [ 0, 1, 2, 3 ].combination(2).each do |a, b|
      next if sol_outcome.(a) == sol_outcome.(b)

      winner, loser = sol_outcome.(a) > sol_outcome.(b) ? [ a, b ] : [ b, a ]
      expected[winner] += 3
      expected[loser] -= 3
    end
    assert_equal expected, result["points"]
    assert_equal expected, message_for(outcome, host).payload["state"]["score"]["totals"]
    assert_equal 1, @scheduler.deals.size, "the next runde follows"
  end

  private

  def surroundings(seed: 0) = Table::Surroundings.new(clock: @clock, scheduler: @scheduler, shuffler: Random.new(seed), random: Random.new(seed))

  def started_table
    waiting = WaitingTable.set_up(user: @host, game: "esmakker", surroundings:).table
    @players.drop(1).each_with_index { |user, index| waiting.sit(user:, seat: index + 1, surroundings:) }
    Table.find(waiting.reload.start(user: @host, surroundings:).table.id)
  end

  def user_at(table, seat) = User.find(table.seating.occupants.fetch(seat).user_id)
  def engine_round(table) = Game.find(table.current_game.id).engine_round

  def play_out(table)
    outcome = nil
    loop do
      round = engine_round(table)
      return outcome if round.complete?

      outcome = player_acts(table, :play, player: user_at(table, round.to_act), card: round.view_for(round.to_act)[:play][:legal_moves].first, surroundings:)
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
