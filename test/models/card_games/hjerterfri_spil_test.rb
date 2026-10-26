require "test_helper"

# What a hjerterfri spil is at the bord, without ActiveRecord: the rows and
# the spil it reads are plain stand-ins.
class HjerterfriSpilTest < ActiveSupport::TestCase
  Row = Struct.new(:number, :deal, :pass_direction, :passes, :plays, :moon_choice, keyword_init: true)
  Spil = Struct.new(:engine_round, :engine_game, :human_seats, keyword_init: true)

  setup { @rules = Hjerterfri::Rules.standard }

  test "a runde is dealt as its row's columns: the deal and the runde's pass direction" do
    row = HjerterfriSpil.deal(4, shuffler: Random.new(1))

    assert_equal [ 4, "none" ], row.values_at(:number, :pass_direction)
    assert_equal Hjerterfri::Deal.shuffled(shuffler: Random.new(1)).to_s, row[:deal]
    assert_equal "left", HjerterfriSpil.deal(1, shuffler: Random.new(1), after: :ignored)[:pass_direction]
  end

  test "the engine's runde is rebuilt from a row, and a row needs a pass direction" do
    row = Row.new(**HjerterfriSpil.deal(1, shuffler: Random.new(1)), passes: "", plays: "", moon_choice: nil)

    round = HjerterfriSpil.engine_round(row, @rules)

    assert_equal Hjerterfri::Round.from_strings(rules: @rules, deal: row.deal, plays: "", pass_direction: "left"), round
    assert_empty HjerterfriSpil.round_errors(row)
    assert_equal [ [ :pass_direction, :blank ] ], HjerterfriSpil.round_errors(row.dup.tap { |blank| blank.pass_direction = "" })
  end

  test "the spil lasts to the end score, keeps each runde's points, and the lowest total wins" do
    game = HjerterfriSpil.engine_game(rules: @rules, results: [ [ 1, 2, 3, 20 ] ], runder: 10)

    assert_equal Hjerterfri::Game.new(rules: @rules, results: [ [ 1, 2, 3, 20 ] ]), game
    assert_not HjerterfriSpil.counts_runder?
    assert_equal 1, HjerterfriSpil.best_total([ 5, 1, 9, 3 ])
    assert_equal 58, HjerterfriSpil.steps_per_runde
    assert_equal [ 1, 2, 3, 20 ], HjerterfriSpil.runde_result(Data.define(:points, :result).new(points: [ 1, 2, 3, 20 ], result: :not_kept))
  end

  test "the seats act at the same time in the bytte, and a runde is never dealt again" do
    round = Hjerterfri::Round.new(rules: @rules, deal: Hjerterfri::Deal.shuffled(shuffler: Random.new(1)), pass_direction: :left)

    assert HjerterfriSpil.simultaneous?(round)
    assert_not HjerterfriSpil.simultaneous?(Hjerterfri::Round.new(rules: @rules, deal: round.deal))
    assert_not HjerterfriSpil.redeal?(round)
  end

  test "its state shows the points taken and the score sheet, with the humans among the lowest as vindere" do
    round = Hjerterfri::Round.new(rules: @rules, deal: Hjerterfri::Deal.shuffled(shuffler: Random.new(1)))
    game = Hjerterfri::Game.new(rules: @rules, results: [ [ 100, 0, 0, 26 ] ])

    state = HjerterfriSpil.state(Spil.new(engine_round: round, engine_game: game, human_seats: [ 0, 1 ]))

    assert_equal [ 0, 0, 0, 0 ], state[:points_taken]
    assert_equal({ end_score: 100, rows: game.rows, totals: [ 100, 0, 0, 26 ], leaders: [ 1, 2 ], winners: [ 1 ] }, state[:score])
  end

  test "a bot passes in the bytte as its strategy chooses" do
    round = Hjerterfri::Round.new(rules: @rules, deal: Hjerterfri::Deal.shuffled(shuffler: Random.new(1)), pass_direction: :left)
    spil = Spil.new(engine_round: round, engine_game: Hjerterfri::Game.new(rules: @rules), human_seats: [])

    decision = HjerterfriSpil.bot_decision(spil, 2, level: :mellem, random: Random.new(0))

    cards = Hjerterfri::Bot.new(level: :mellem, random: Random.new(0)).choose_pass(round.view_for(2))
    assert_equal Hjerterfri::Pass.new(cards:), decision.intent
    assert_equal({ decision: "pass", choice: cards, reason: "mellem_pass" }, decision.thought)
  end

  test "no step has a deadline" do
    round = Hjerterfri::Round.new(rules: @rules, deal: Hjerterfri::Deal.shuffled(shuffler: Random.new(1)))
    at = Time.utc(2026, 10, 26, 12)

    assert_nil HjerterfriSpil.deadline(round, @rules, intent: Hjerterfri::Play.new(card: "2C"), at:, current: nil)
    assert_nil HjerterfriSpil.past_deadline(Hjerterfri::Play.new(card: "2C"), deadline_at: at, at:)
    assert_nil HjerterfriSpil.at_deadline(round)
  end
end
