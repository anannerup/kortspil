require "test_helper"

# Seam 2 for ticket 05: a runde's points through the bord's actions. The
# vært's point values are the ones scored with, every seat sees each
# runde's points and the running totals, and the spil's stored runder
# replay to the same totals.
#
# Seats: the vært (seat 0) deals runde 1, so erik (seat 1) is forhånd,
# then frida (2) and admin (3).
class EsmakkerPointsTableTest < ActiveSupport::TestCase
  setup do
    @host = users(:approved)
    @players = [ @host, users(:erik), users(:frida), users(:admin) ]
    @scheduler = FakeScheduler.new
    @clock = FakeClock.new
  end

  test "a runde's points, by the vært's point values, reach every seat's totals and sum to zero" do
    table = started_table(points: { stakes: { "8" => "2" }, trumflos: "3" })
    _host, erik, = @players
    outcome = play_runde(table, erik, "8", trump: "trumfloes")

    result = Game.find(table.current_game.id).engine_round.result
    over = result.stik - 8
    per_pair = over.negative? ? 2 * -over * 3 : (2 + over) * 3
    side = result.side
    winners = result.gik_hjem? ? side : (0..3).to_a - side
    alone = [ winners, (0..3).to_a - winners ].find(&:one?)
    expected = (0..3).map { |seat| (winners.include?(seat) ? 1 : -1) * per_pair * (alone&.include?(seat) ? 3 : 1) }
    assert_equal expected, result.points, "stake 2 and trumfløs 3, as the vært set them"
    assert_equal 0, expected.sum

    @players.each do |player|
      score = state_of(outcome, player)["score"]
      assert_equal expected, score["totals"], "#{player.username} sees the totals"
      assert_equal [ expected ], score["results"].map { |row| row["points"] }
      assert_equal [ expected ], score["results"].map { |row| row["totals"] }
      assert_equal expected, view_of(outcome, player)["result"]["points"], "the runde's result says who won what"
      assert_equal [ expected.index(expected.max) ], score["leaders"] if expected.count(expected.max) == 1
    end
  end

  test "a bordlægger scores the vært's amount, and the spil's stored runder replay to the same totals" do
    table = started_table(runder: 3, points: { bordlaegger: "7" })
    host, erik, frida, admin = @players

    play_runde(table, erik, "9", trump: "H")
    game = table.current_game
    table.next_runde(game_id: game.id, number: 2, surroundings:)
    win_bidding(table, frida, "bordlaegger")
    keep_kitty(table)
    play_out(table)
    table.next_runde(game_id: game.id, number: 3, surroundings:)
    outcome = play_runde(table, admin, "8gode")

    finished = Game.find(game.id)
    assert finished.finished?
    results = finished.engine_game.results
    frida_seat = table.seating.seat_of(frida)
    sign = results[1].vaeltet.include?(frida_seat) ? -1 : 1
    assert_equal (0..3).map { |seat| seat == frida_seat ? sign * 21 : sign * -7 }, results[1].points, "7 from each modspiller"
    assert results.values_at(0, 2).all? { |result| result.points.any?(&:nonzero?) }
    totals = results.map(&:points).transpose.map(&:sum)
    assert_equal totals, finished.final_scores
    assert_equal 0, totals.sum
    assert_equal totals, state_of(outcome, host)["score"]["totals"]
    assert_equal totals, state_of(outcome, host)["score"]["results"].last["totals"]

    rules = finished.engine_rules
    replayed = finished.rounds.map { |row| Esmakker::Round.from_strings(rules:, deal: row.deal, dealer: row.dealer, actions: row.actions).result }
    assert_equal results.map(&:points), replayed.map(&:points), "each stored runde replays to its points"
    assert_equal totals, Esmakker::Game.new(rules:, runder: 3, results: replayed).totals

    best = (0..3).select { |seat| totals[seat] == totals.max }
    assert_equal best.map { |seat| @players[seat].id }.sort, finished.winner_ids.sort, "at es-makker the highest total wins"
  end

  private

  def surroundings(seed: 0) = Table::Surroundings.new(clock: @clock, scheduler: @scheduler, shuffler: Random.new(seed), random: Random.new(seed))

  # The stored es-makker bord with its spil started, the vært's `points`
  # set on the settings form before the start.
  def started_table(runder: nil, points: {})
    waiting = WaitingTable.set_up(user: @host, game: "esmakker", surroundings:).table
    outcome = waiting.change_settings(user: @host, rules: { bank_window: "8", points: }, kind: "open", runder: "10", surroundings:)
    assert_not outcome.refused?
    @players.drop(1).each_with_index { |user, index| waiting.reload.sit(user:, seat: index + 1, surroundings:) }
    table = waiting.reload.start(user: @host, surroundings:).table
    table.update_column(:runder, runder) if runder
    Table.find(table.id)
  end

  # `player` (the forhånd) wins `melding`, names `trump` (unless gode),
  # calls the first ace she may, lays the kitty back and the runde is
  # played out with each seat's first legal card.
  def play_runde(table, player, melding, trump: nil)
    win_bidding(table, player, melding)
    seat = table.seating.seat_of(player)
    table.choose_trump(player:, trump:, surroundings:) if trump
    outcome = table.call_ace(player:, suit: engine_view(table, seat)[:choices][:aces].first, surroundings:)
    table.discard(player:, cards: view_of(outcome, player)["play"]["kitty_cards"], surroundings:)
    play_out(table)
  end

  def win_bidding(table, player, melding)
    seat = table.seating.seat_of(player)
    outcome = table.bid(player:, melding:, surroundings:)
    3.times { |offset| outcome = table.pas(player: user_at(table, (seat + 1 + offset) % 4), surroundings:) }
    outcome
  end

  def user_at(table, seat) = User.find(table.seating.occupants.fetch(seat).user_id)
  def engine_view(table, seat) = Game.find(table.current_game.id).engine_round.view_for(seat)

  # At a sol-melding each seat in turn lays the kitty back (keeps its hand).
  def keep_kitty(table)
    loop do
      round = Game.find(table.current_game.id).engine_round
      return unless round.phase == :exchanging

      table.discard(player: user_at(table, round.to_act), cards: round.view_for(round.to_act)[:play][:kitty_cards], surroundings:)
    end
  end

  def play_out(table)
    outcome = nil
    loop do
      round = Game.find(table.current_game.id).engine_round
      return outcome if round.complete?

      seat = round.to_act
      outcome = table.play(player: user_at(table, seat), card: round.view_for(seat)[:play][:legal_moves].first, surroundings:)
    end
  end

  def message_for(outcome, user) = outcome.messages.find { |message| message.user_id == user.id }
  def state_of(outcome, user) = message_for(outcome, user).payload["state"]
  def view_of(outcome, user) = state_of(outcome, user)["view"]
end
