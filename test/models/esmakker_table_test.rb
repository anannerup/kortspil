require "test_helper"

# Seam 2 for es-makker (ticket 01): an es-makker bord made in the lobby,
# its settings (the number of runder and es-makker's GameRules), the start
# with four humans only (no bots), and the stored bord and spil that
# record they are es-makker, with runde 1 dealt and replayed from storage.
class EsmakkerTableTest < ActiveSupport::TestCase
  setup do
    @host = users(:approved)
    @players = [ @host, users(:erik), users(:frida), users(:admin) ]
    @scheduler = FakeScheduler.new
  end

  test "an es-makker bord plays es-makker with REGLER §2.0's rules and 10 runder" do
    table = create_table

    assert_equal "esmakker", table.game
    assert_equal Esmakker::Rules.standard, table.rules.game
    assert_equal 10, table.rules.runder
    entry = table.lobby_entry
    assert_equal [ "esmakker", 10, false ], entry.values_at("game", "runder", "bots_allowed")
    assert_equal %w[vip halve gode], entry["rules"]["pahaeng_order"]
  end

  test "a hjerterfri bord has no number of runder and takes bots" do
    table = WaitingTable.set_up(user: @host, surroundings:).table

    assert_nil table.rules.runder
    assert_equal [ "hjerterfri", nil, true ], table.lobby_entry.values_at("game", "runder", "bots_allowed")
  end

  test "the vært sets the runder and es-makker's rules from the settings form; others may not" do
    table = create_table
    form = { pahaeng_order: "halve,vip,gode", joker_trumpable: "1", esmakker_banks_first: "0", bank_window: "6",
             points: { stakes: { "8" => "2", "13" => "4,5" }, sol: "3.5" } }

    assert_equal :not_host, table.change_settings(user: users(:erik), rules: form, kind: "open", runder: "15", surroundings:).refusal
    outcome = table.change_settings(user: @host, rules: form, kind: "private", runder: "15", surroundings:)

    assert_not outcome.refused?
    rules = table.reload.rules
    assert_equal [ "private", 15 ], [ rules.kind, rules.runder ]
    assert_equal %w[halve vip gode], rules.game.pahaeng_order
    assert_equal [ true, false, 6 ], [ rules.game.joker_trumpable, rules.game.esmakker_banks_first, rules.game.bank_window ]
    assert_equal [ 2, 1.5, 4.5 ], rules.game.points.stakes.values_at("8", "9", "13")
    assert_equal 3.5, rules.game.points.sol
  end

  test "settings the rules cannot hold are refused and change nothing" do
    table = create_table

    assert_equal :invalid_runder, table.change_settings(user: @host, rules: {}, kind: "open", runder: "0", surroundings:).refusal
    assert_equal :invalid_runder, table.change_settings(user: @host, rules: {}, kind: "open", runder: "ti", surroundings:).refusal
    assert_equal :invalid_rules, table.change_settings(user: @host, rules: { bank_window: "11" }, kind: "open", runder: "10", surroundings:).refusal
    assert_equal :invalid_rules, table.change_settings(user: @host, rules: { bank_window: "8", pahaeng_order: %w[vip vip gode] }, kind: "open", runder: "10", surroundings:).refusal
    assert_equal Rules.standard(game: "esmakker"), table.reload.rules
  end

  test "no bots at an es-makker bord" do
    table = create_table

    assert_equal :no_bots_for_game, table.add_bot(user: @host, seat: 1, surroundings:).refusal
    assert table.reload.occupants.fetch(1).empty?
  end

  test "the spil starts only when four humans sit at the bord" do
    table = create_table
    @players.drop(1).first(2).each_with_index { |user, index| table.sit(user:, seat: index + 1, surroundings:) }

    assert_equal :seats_not_filled, table.start(user: @host, surroundings:).refusal
    assert_no_difference "Table.count" do
      # A bot that came in with the seats of a finished spil cannot start one.
      waiting = table.reload.with(seats: table.reload.seats.dup.tap { |seats| seats[3] = Table::Seating::Occupant.new(seat: 3, user_id: nil, name: "Bot 1", bot_level: :mellem) }.freeze)
      WaitingTables.default.change(table.id) { [ waiting, nil ] }
      assert_equal :needs_four_humans, table.start(user: @host, surroundings:).refusal
    end
  end

  test "starting stores an es-makker bord and spil, and deals 13 cards to each seat and 3 to the kitty" do
    stored = full_table.start(user: @host, surroundings:).table
    game = stored.current_game

    assert_equal [ "esmakker", "esmakker" ], [ stored.game, game.game ]
    assert_equal 10, stored.reload.rules.runder
    assert_equal Esmakker::Rules.standard, game.engine_rules
    round = game.current_round
    assert_equal [ 1, 0 ], [ round.number, round.dealer ]
    assert_nil round.pass_direction
    assert_equal 55, round.deal.split.size
    assert_equal "", round.actions
  end

  test "each seat is sent only its own 13 cards, who deals and who is forhånd" do
    outcome = full_table.start(user: @host, surroundings:)
    deal = Esmakker::Deal.parse(outcome.table.current_game.current_round.deal)

    assert_equal 4, outcome.messages.size
    outcome.messages.each do |message|
      state = message.payload["state"]
      view = state["view"]
      assert_equal [ "esmakker", 10, "bidding" ], [ state["game"], state["runder"], view["phase"] ]
      assert_equal deal.hand(message.seat).map(&:to_s).sort, view["hand"].sort
      assert_equal [ 0, 1, 3 ], [ view["dealer"], view["forhand"], view["kitty_count"] ]
      others = (deal.hands.each_with_index.reject { |_, seat| seat == message.seat }.flat_map(&:first) + deal.kitty).map(&:to_s)
      assert_empty others & message.payload.to_json.scan(/"([2-9TJQKA][CDHS]|X\d)"/).flatten
    end
  end

  test "nobody is to act before the meldingsrunde, so nobody's turn is timed and no bot is woken" do
    outcome = full_table.start(user: @host, surroundings:)

    assert_empty outcome.table.current_game.seats_to_act
    assert outcome.messages.all? { |message| message.payload["state"]["seats"].all? { |seat| seat["seconds_left"].nil? } }
    assert_empty @scheduler.turns
    assert_empty @scheduler.deals
  end

  test "the stored runde replays to the same state, and the kortgiver moves clockwise each runde" do
    stored = full_table.start(user: @host, surroundings:).table
    game = Game.find(stored.current_game.id)
    before = game.engine_round

    assert_equal before, Game.find(game.id).engine_round
    game.rounds.deal!(2, shuffler: Random.new(5), card_game: "esmakker", dealer: before.next_dealer)
    assert_equal [ 1, 2 ], [ Game.find(game.id).engine_round.dealer, Game.find(game.id).engine_round.forhand ]
  end

  test "a hjerterfri intent at an es-makker bord is rejected to that seat" do
    stored = full_table.start(user: @host, surroundings:).table

    outcome = stored.play(player: @host, card: "2C", surroundings:)

    assert_equal [ "rejected" ], outcome.messages.map { |message| message.payload["type"] }
    assert_equal "unknown_intent", outcome.messages.sole.payload["reason"]
  end

  test "hjerterfri borde stored before es-makker keep loading as hjerterfri" do
    table = started_practice(@host)

    assert_equal "hjerterfri", table.game
    assert_equal "hjerterfri", table.current_game.game
    assert_nil table.rules.runder
    assert_equal "hjerterfri", table.current_game.state_for(0, now: Time.current)[:game]
  end

  private

  def surroundings(seed: 0) = Table::Surroundings.new(scheduler: @scheduler, shuffler: Random.new(seed), random: Random.new(seed))

  def create_table = WaitingTable.set_up(user: @host, game: "esmakker", surroundings:).table

  def full_table
    table = create_table
    @players.drop(1).each_with_index { |user, index| table.sit(user:, seat: index + 1, surroundings:) }
    table.reload
  end
end
