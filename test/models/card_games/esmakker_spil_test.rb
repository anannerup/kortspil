require "test_helper"

# What an es-makker spil is at the bord, without ActiveRecord: the rows and
# the spil it reads are plain stand-ins.
class EsmakkerSpilTest < ActiveSupport::TestCase
  Row = Struct.new(:number, :deal, :dealer, :actions, keyword_init: true)
  Spil = Struct.new(:engine_round, :engine_game, :engine_rules, :deadline_at, keyword_init: true)

  setup { @rules = Esmakker::Rules.standard }

  test "the first runde is dealt by the first kortgiver, the next by the one the runde before names" do
    first = EsmakkerSpil.deal(1, shuffler: Random.new(1))
    assert_equal [ 1, Esmakker::Seats::FIRST_DEALER, Esmakker::Deal.shuffled(shuffler: Random.new(1)).to_s ], first.values_at(:number, :dealer, :deal)

    before = EsmakkerSpil.engine_round(Row.new(**first, actions: ""), @rules)
    assert_equal before.next_dealer, EsmakkerSpil.deal(2, shuffler: Random.new(2), after: before)[:dealer]
  end

  test "the engine's runde is rebuilt from a row, whose kortgiver is a seat" do
    row = Row.new(**EsmakkerSpil.deal(1, shuffler: Random.new(1)), actions: "1:9 2:pas")

    round = EsmakkerSpil.engine_round(row, @rules)

    assert_equal Esmakker::Round.from_strings(rules: @rules, deal: row.deal, dealer: row.dealer, actions: "1:9 2:pas"), round
    assert_empty EsmakkerSpil.round_errors(row)
    assert_equal [ [ :dealer, :inclusion ] ], EsmakkerSpil.round_errors(row.dup.tap { |bad| bad.dealer = nil })
  end

  test "the spil lasts the bord's runder and the highest total wins" do
    assert_equal Esmakker::Game.new(rules: @rules, runder: 7, results: []), EsmakkerSpil.engine_game(rules: @rules, results: [], runder: 7)
    assert EsmakkerSpil.counts_runder?
    assert_equal 9, EsmakkerSpil.best_total([ 5, 1, 9, 3 ])
    assert_equal Esmakker::Round::MAX_STEPS, EsmakkerSpil.steps_per_runde
    assert_equal :kept, EsmakkerSpil.runde_result(Data.define(:points, :result).new(points: [ 1, -1, 0, 0 ], result: :kept))
  end

  test "one seat acts at a time, and a runde everybody passed is dealt again" do
    round = Esmakker::Round.new(rules: @rules, deal: Esmakker::Deal.shuffled(shuffler: Random.new(1)), dealer: 0)
    passed = [ 1, 2, 3, 0 ].reduce(round) { |runde, seat| runde.apply(seat, Esmakker::Bidding::Pas.new).round }

    assert_not EsmakkerSpil.simultaneous?(round)
    assert_not EsmakkerSpil.redeal?(round)
    assert EsmakkerSpil.redeal?(passed)
  end

  test "its state shows the runder, the runde being played and the score, and no bank window outside vip's" do
    round = Esmakker::Round.new(rules: @rules, deal: Esmakker::Deal.shuffled(shuffler: Random.new(1)), dealer: 0)
    spil = Spil.new(engine_round: round, engine_game: Esmakker::Game.new(rules: @rules, runder: 5), engine_rules: @rules, deadline_at: nil)

    state = EsmakkerSpil.state(spil, now: Time.utc(2026, 10, 26))

    assert_equal({ runder: 5, runde: 1, bank_window: nil, score: { totals: [ 0, 0, 0, 0 ], leaders: [], results: [] } }, state)
  end

  test "a bot's turn is the first es-makker bot's, from what its seat may see; a seat not to act does nothing" do
    round = Esmakker::Round.new(rules: @rules, deal: Esmakker::Deal.shuffled(shuffler: Random.new(1)), dealer: 0)

    assert_equal Esmakker::Bidding::Bid.new(melding: Esmakker::Melding.parse("9")), EsmakkerSpil.bot_intent(Spil.new(engine_round: round), 1, level: :mellem, random: Random.new(0))
    assert_nil EsmakkerSpil.bot_intent(Spil.new(engine_round: round), 2, level: :mellem, random: Random.new(0))
  end

  test "the deadline is vip's bank window: it opens when the melder laid away, starts again on a bank, and closes in the melder's name" do
    at = Time.utc(2026, 10, 26, 12)
    later = at + 3
    banking = Data.define(:banking?, :play).new(banking?: true, play: Data.define(:melder).new(melder: 1))
    playing = Data.define(:banking?).new(banking?: false)
    seconds = @rules.bank_window

    assert_equal at + seconds, EsmakkerSpil.deadline(banking, @rules, intent: Esmakker::Discard.new(cards: []), at:, current: nil), "opens"
    assert_equal at + seconds, EsmakkerSpil.deadline(banking, @rules, intent: Esmakker::TurnCard.new, at: later, current: at + seconds), "keeps"
    assert_equal later + seconds, EsmakkerSpil.deadline(banking, @rules, intent: Esmakker::Bank.new, at: later, current: at + seconds), "starts again"
    assert_nil EsmakkerSpil.deadline(playing, @rules, intent: Esmakker::Bank.new, at: later, current: at + seconds), "closed"

    assert_equal :bank_window_closed, EsmakkerSpil.past_deadline(Esmakker::Bank.new, deadline_at: at, at:)
    assert_nil EsmakkerSpil.past_deadline(Esmakker::Bank.new, deadline_at: later, at:)
    assert_nil EsmakkerSpil.past_deadline(Esmakker::Bidding::Pas.new, deadline_at: at, at: later)

    assert_equal [ 1, Esmakker::CloseBankWindow.new ], EsmakkerSpil.at_deadline(banking)
    assert_nil EsmakkerSpil.at_deadline(playing)
  end
end
