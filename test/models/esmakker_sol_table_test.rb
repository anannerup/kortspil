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
    table.bid(player: erik, melding: "sol", surroundings:)
    table.gaa_med(player: frida, surroundings:)
    table.pas(player: admin, surroundings:)
    outcome = table.pas(player: host, surroundings:)

    @players.each do |player|
      view = view_of(outcome, player)
      assert_equal [ "exchanging", 1 ], view.values_at("phase", "to_act")
      assert_equal [ "sol", [ 1, 2 ], [ 1, 2, 3, 0 ], 1 ], view["play"].values_at("kind", "players", "exchange_order", "exchanging")
    end
    kitty = view_of(outcome, erik)["play"]["kitty_cards"]
    assert_equal [ 3, 16, true ], [ kitty.size, view_of(outcome, erik)["hand"].size, view_of(outcome, erik)["choices"]["discard"] ]
    [ host, frida, admin ].each { |player| assert_empty kitty & cards_in(message_for(outcome, player).payload), "#{player.username} never sees the kitty" }
    assert_rejected :not_now, table.choose_trump(player: erik, trump: "H", surroundings:), erik
    assert_rejected :not_your_turn, table.discard(player: frida, cards: kitty, surroundings:), frida

    # Erik takes one kitty card and lays one of his own away; the other two go on to frida.
    own = view_of(outcome, erik)["hand"].find { |code| !kitty.include?(code) }
    outcome = table.discard(player: erik, cards: [ own, *kitty.drop(1) ], surroundings:)
    assert_equal [ own ], view_of(outcome, erik)["play"]["discarded"]
    [ host, frida, admin ].each { |player| assert_not_includes cards_in(message_for(outcome, player).payload), own }
    assert_equal [ 2, kitty.drop(1).sort ], [ view_of(outcome, frida)["to_act"], view_of(outcome, frida)["play"]["kitty_cards"].sort ]

    outcome = table.discard(player: frida, cards: kitty.drop(1), surroundings:)
    outcome = table.discard(player: admin, cards: view_of(outcome, admin)["play"]["kitty_cards"], surroundings:)
    outcome = table.discard(player: host, cards: view_of(outcome, host)["play"]["kitty_cards"], surroundings:)
    assert_equal [ "playing", 1 ], view_of(outcome, host).values_at("phase", "to_act"), "the forhånd leads"

    outcome = play_out(table)
    result = view_of(outcome, host)["result"]
    assert_equal [ "sol", [ 1, 2 ], 1 ], [ result["kind"], result["sol"]["players"], result["sol"]["most_stik"] ]
    vaeltet = result["sol"]["vaeltet"]
    # Each pair settles once, the better outcome getting 3 from the other.
    outcome = ->(seat) { [ 1, 2 ].include?(seat) ? (vaeltet.include?(seat) ? -1 : 1) : 0 }
    expected = [ 0, 0, 0, 0 ]
    [ 0, 1, 2, 3 ].combination(2).each do |a, b|
      next if outcome.(a) == outcome.(b)

      winner, loser = outcome.(a) > outcome.(b) ? [ a, b ] : [ b, a ]
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

      outcome = table.play(player: user_at(table, round.to_act), card: round.view_for(round.to_act)[:play][:legal_moves].first, surroundings:)
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
