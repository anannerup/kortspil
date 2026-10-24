require "test_helper"

# The result of a spil as stored (GLOSSARY.md: Forlade, Vinder, Afbrudt):
# who forlod it and who won, from the seats snapshot, the seat_log and the
# final totals.
class GameResultTest < ActiveSupport::TestCase
  setup do
    @players = [ users(:approved), users(:admin), users(:erik), users(:frida) ]
    @table = Table.create!(host: @players.first, kind: :open, status: :playing, rules: Hjerterfri::Rules.standard.to_h)
  end

  test "the human with the lowest total wins" do
    assert_equal [ @players[1].id ], finished([ 100, 40, 60, 80 ]).winner_ids
  end

  test "humans tied for the lowest total share the win" do
    assert_equal [ @players[1].id, @players[3].id ], finished([ 100, 40, 60, 40 ]).winner_ids
  end

  test "a human tied with a bot still wins" do
    game = finished([ 100, 40, 60, 40 ], bots: { 1 => "Bot 1" })

    assert_equal [ @players[3].id ], game.winner_ids
  end

  test "a bot alone with the lowest total means no vinder" do
    assert_empty finished([ 100, 20, 60, 40 ], bots: { 1 => "Bot 1" }).winner_ids
  end

  test "a player who forlod lost, even with the lowest total; the bot in their seat does not win either" do
    game = finished([ 100, 20, 60, 40 ], seat_log: [ { "seat" => 1, "from" => @players[1].id, "to" => "Bot 1", "at_play" => 30 } ])

    assert_equal [ @players[1].id ], game.forladt_ids
    assert_empty game.winner_ids
    assert_equal({ "kind" => "bot", "name" => "Bot 1" }, game.holders[1])
  end

  test "an afbrudt spil has no vinder, and its last leaver lost it too" do
    game = @table.games.create!(seats: human_seats, rules: {}, status: :abandoned, final_scores: [ 10, 0, 0, 0 ], forfeited_by: @players[0],
      seat_log: [ { "seat" => 1, "from" => @players[1].id, "to" => "Bot 1", "at_play" => 3 } ])

    assert_empty game.winner_ids
    assert_equal [ @players[1].id, @players[0].id ], game.forladt_ids
  end

  private

  def human_seats = @players.map { |player| { "kind" => "human", "user_id" => player.id } }

  def finished(totals, bots: {}, seat_log: [])
    seats = human_seats.each_with_index.map { |entry, seat| bots[seat] ? { "kind" => "bot", "name" => bots[seat] } : entry }
    @table.games.create!(seats:, rules: {}, status: :finished, final_scores: totals, seat_log:)
  end
end
