require "test_helper"

# Husets regler (GLOSSARY.md, REGLER §2.0; Anders: "hvis man spiller med
# bots spiller man med husets regler"): while a bot sits at a waiting bord,
# the card game's rules are its rules for bots, the standard ones; how long
# the spil lasts (hjerterfri's end score, es-makker's number of runder)
# and the bord's type stay the vært's. The spil starts with them.
class HouseRulesTest < ActiveSupport::TestCase
  setup do
    @host = users(:approved)
    @scheduler = FakeScheduler.new
  end

  HJERTERFRI = Hjerterfri::Rules.new(end_score: 60, queen_breaks_hearts: true, jack_of_diamonds_minus_ten: true, shooters_choice: true)
  ESMAKKER = Esmakker::Rules.new(pahaeng_order: %w[gode halve vip], joker_trumpable: true, esmakker_banks_first: false, bank_window: 5,
                                 afkast: "spil_den_her", points: Esmakker::Points.standard.with(sol: 9))

  test "a hjerterfri bord without bots keeps the vært's rules; a bot brings husets regler, with the end score kept" do
    table = WaitingTable.set_up(user: @host, rules: HJERTERFRI, surroundings:).table
    assert_equal HJERTERFRI, table.rules.game
    assert_not table.lobby_entry["house_rules"]

    table = table.add_bot(user: @host, seat: 1, surroundings:).table

    assert_equal Hjerterfri::Rules.new(end_score: 60), table.rules.game
    assert table.lobby_entry["house_rules"]
    assert_equal false, table.lobby_entry["rules"]["shooters_choice"]
  end

  test "while a bot sits there, the vært's settings change the end score and the type, never the house rules" do
    table = with_bot(WaitingTable.set_up(user: @host, surroundings:).table)

    outcome = table.change_settings(user: @host, rules: { end_score: "40", queen_breaks_hearts: "1", shooters_choice: "1" }, kind: "private", surroundings:)

    assert_not outcome.refused?
    after = table.reload
    assert_equal [ "private", Hjerterfri::Rules.new(end_score: 40) ], [ after.kind, after.rules.game ]
    assert_equal :invalid_end_score, table.change_settings(user: @host, rules: { end_score: "0" }, kind: "open", surroundings:).refusal
  end

  test "once the bot is gone the vært may choose the house rules again" do
    table = with_bot(WaitingTable.set_up(user: @host, surroundings:).table)
    table = table.remove_bot(user: @host, seat: 1, surroundings:).table

    table.change_settings(user: @host, rules: HJERTERFRI, kind: "open", surroundings:)

    assert_equal HJERTERFRI, table.reload.rules.game
  end

  test "a hjerterfri spil started with a bot is played by husets regler" do
    table = WaitingTable.set_up(user: @host, rules: HJERTERFRI, surroundings:).table
    (1..3).each { |seat| table.add_bot(user: @host, seat:, surroundings:) }

    stored = table.start(user: @host, surroundings:).table

    assert_equal Hjerterfri::Rules.new(end_score: 60), stored.current_game.engine_rules
    assert stored.lobby_entry["house_rules"]
  end

  test "a hjerterfri spil among four humans keeps the vært's rules" do
    table = WaitingTable.set_up(user: @host, rules: HJERTERFRI, surroundings:).table
    [ users(:erik), users(:frida), users(:admin) ].each_with_index { |user, index| table.sit(user:, seat: index + 1, surroundings:) }

    stored = table.start(user: @host, surroundings:).table

    assert_equal HJERTERFRI, stored.current_game.engine_rules
    assert_not stored.lobby_entry["house_rules"]
  end

  test "an es-makker bord with a bot plays the standard rules for its chosen number of runder" do
    table = WaitingTable.set_up(user: @host, game: "esmakker", rules: ESMAKKER, surroundings:).table
    table.change_settings(user: @host, rules: ESMAKKER, kind: "open", runder: "20", surroundings:)
    assert_equal ESMAKKER, table.reload.rules.game

    table = with_bot(table)
    assert_equal [ Esmakker::Rules.standard, 20 ], [ table.rules.game, table.rules.runder ]

    table = table.change_settings(user: @host, rules: ESMAKKER, kind: "open", runder: "12", surroundings:).table
    assert_equal [ Esmakker::Rules.standard, 12 ], [ table.rules.game, table.rules.runder ]

    [ users(:erik), users(:frida) ].each_with_index { |user, index| table.sit(user:, seat: index + 2, surroundings:) }
    stored = table.start(user: @host, surroundings:).table
    assert_equal [ Esmakker::Rules.standard, 12 ], [ stored.current_game.engine_rules, stored.rules.runder ]
  end

  test "an es-makker øvebord plays husets regler, whatever its form said" do
    table = WaitingTable.set_up_practice(user: @host, game: "esmakker", rules: ESMAKKER, surroundings:).table

    assert_equal Esmakker::Rules.standard, table.rules.game
    table = table.change_settings(user: @host, rules: ESMAKKER, runder: "7", surroundings:).table
    assert_equal [ Esmakker::Rules.standard, 7 ], [ table.rules.game, table.rules.runder ]
  end

  test "the next spil's bord keeps husets regler while bots sit at it" do
    table = WaitingTable.set_up(user: @host, rules: HJERTERFRI, surroundings:).table
    [ users(:erik), users(:frida), users(:admin) ].each_with_index { |user, index| table.sit(user:, seat: index + 1, surroundings:) }
    stored = table.start(user: @host, surroundings:).table
    occupants = stored.seating.occupants.dup
    occupants[3] = Table::Seating::Occupant.new(seat: 3, user_id: nil, name: "Bot 1", bot_level: :mellem)

    after = WaitingTable.after_spil(stored, occupants)

    assert_equal Hjerterfri::Rules.new(end_score: 60), after.rules.game
  end

  private

  def surroundings = Table::Surroundings.new(scheduler: @scheduler, shuffler: Random.new(0), random: Random.new(0))

  def with_bot(table) = table.add_bot(user: @host, seat: 1, surroundings:).table
end
