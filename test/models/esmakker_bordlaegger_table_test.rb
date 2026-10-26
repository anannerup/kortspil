require "test_helper"

# Seam 2 for ticket 10: a whole bordlægger runde through the bord's
# actions (bid and gaa_med; discard for each seat's turn at the kitty;
# play), each answered with every seat's state: the melder's cards hidden
# until the first stik is taken, then open to every seat; the settlement
# per sol player with the bord's amount, and the next runde.
#
# Seats: the vært (seat 0) deals runde 1, so erik (seat 1) is forhånd,
# then frida (2) and admin (3).
class EsmakkerBordlaeggerTableTest < ActiveSupport::TestCase
  setup do
    @host = users(:approved)
    @players = [ @host, users(:erik), users(:frida), users(:admin) ]
    @scheduler = FakeScheduler.new
    @clock = FakeClock.new
  end

  test "a whole bordlægger runde: erik bids it, frida goes with; erik's cards open to all after stik 1, frida's never; each settled for 5" do
    table = started_table
    host, erik, frida, admin = @players
    table.bid(player: erik, melding: "bordlaegger", surroundings:)
    table.gaa_med(player: frida, surroundings:)
    table.pas(player: admin, surroundings:)
    outcome = table.pas(player: host, surroundings:)
    @players.each { |player| assert_equal [ "sol", [ 1, 2 ], nil ], view_of(outcome, player)["play"].values_at("kind", "players", "open_hand") }

    outcome = keep_kitty(table)
    assert_equal [ "playing", 1 ], view_of(outcome, host).values_at("phase", "to_act"), "the forhånd leads"

    # Stik 1: nobody sees erik's hand, even with stik 1 under way.
    3.times { outcome = play_first_legal(table) }
    erik_hand = view_of(outcome, erik)["hand"]
    [ host, frida, admin ].each do |player|
      assert_nil view_of(outcome, player)["play"]["open_hand"]
      assert_empty erik_hand & cards_in(message_for(outcome, player).payload), "#{player.username} doesn't see erik's cards before stik 1"
    end

    outcome = play_first_legal(table)
    erik_hand = view_of(outcome, erik)["hand"]
    frida_hand = view_of(outcome, frida)["hand"]
    assert_equal 12, erik_hand.size
    @players.each do |player|
      assert_equal({ "seat" => 1, "cards" => erik_hand }, view_of(outcome, player)["play"]["open_hand"], "#{player.username} sees erik's open hand")
    end
    [ host, admin ].each { |player| assert_empty frida_hand & cards_in(message_for(outcome, player).payload), "frida's cards stay hidden from #{player.username}" }

    outcome = play_out(table)
    result = view_of(outcome, host)["result"]
    assert_equal [ "sol", "bordlaegger", [ 1, 2 ], 1 ], [ result["kind"], result["melding"], result["sol"]["players"], result["sol"]["most_stik"] ]
    expected = [ 0, 0, 0, 0 ]
    [ 1, 2 ].each do |player|
      sign = result["sol"]["vaeltet"].include?(player) ? -5 : 5
      [ 0, 3 ].each { |modspiller| expected[player] += sign; expected[modspiller] -= sign }
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

  # Each seat in turn lays the kitty back (keeps its hand).
  def keep_kitty(table)
    outcome = nil
    loop do
      round = engine_round(table)
      return outcome unless round.phase == :exchanging

      outcome = table.discard(player: user_at(table, round.to_act), cards: round.view_for(round.to_act)[:play][:kitty_cards], surroundings:)
    end
  end

  def play_first_legal(table)
    round = engine_round(table)
    table.play(player: user_at(table, round.to_act), card: round.view_for(round.to_act)[:play][:legal_moves].first, surroundings:)
  end

  def play_out(table)
    outcome = nil
    outcome = play_first_legal(table) until engine_round(table).complete?
    outcome
  end

  def message_for(outcome, user) = outcome.messages.find { |message| message.user_id == user.id }
  def view_of(outcome, user) = message_for(outcome, user).payload["state"]["view"]
  def cards_in(payload) = payload.to_json.scan(/"([2-9TJQKA][CDHS]|X\d)"/).flatten.uniq
end
