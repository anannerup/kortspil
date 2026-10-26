require "test_helper"

# Seam 2 for es-makker's meldingsrunde (ticket 02): whole meldingsrunder
# through the bord's actions (bid, pas, "det kan jeg selv", gå med,
# jernhånd), each answered with every seat's state; the redeal after all
# pass or a jernhånd, dealt as the next round row by the right kortgiver.
#
# Seats: the vært (seat 0) deals runde 1, so erik (seat 1) is forhånd,
# then frida (2) and admin (3).
class EsmakkerBiddingTableTest < ActiveSupport::TestCase
  setup do
    @host = users(:approved)
    @players = [ @host, users(:erik), users(:frida), users(:admin) ]
    @scheduler = FakeScheduler.new
    @clock = FakeClock.new
  end

  test "a duel with repeated det kan jeg selv ends with a melder that every seat is shown" do
    table = started_table
    host, erik, frida, admin = @players

    outcome = player_acts(table, :bid, player: erik, melding: "9", surroundings:)
    assert_equal [ 2, "9", 1 ], bidding_of(outcome, frida).values_at("to_act", "melding", "holder")
    assert_equal Esmakker::Ladder.standard.above(Esmakker::Melding.parse("9")).map(&:to_s), choices_of(outcome, frida)["meldinger"]

    outcome = player_acts(table, :bid, player: frida, melding: "10", surroundings:)
    assert_equal [ 1, 1 ], bidding_of(outcome, erik).values_at("to_act", "serveret")
    assert_equal({ "meldinger" => [], "det_kan_jeg_selv" => true, "gaa_med" => false, "pas" => true, "jernhaand" => false,
                   "trumps" => [], "aces" => [], "turn_card" => false, "accept_trump" => false, "bank" => false, "discard" => false, "fordaekt" => [] }, choices_of(outcome, erik))

    outcome = player_acts(table, :det_kan_jeg_selv, player: erik, surroundings:)
    assert_equal [ 2, "10", 1 ], bidding_of(outcome, host).values_at("to_act", "melding", "holder")

    player_acts(table, :bid, player: frida, melding: "10halve", surroundings:)
    outcome = player_acts(table, :det_kan_jeg_selv, player: erik, surroundings:)
    assert_equal [ "10halve", 1 ], bidding_of(outcome, admin).values_at("melding", "holder")

    player_acts(table, :pas, player: frida, surroundings:)
    outcome = player_acts(table, :pas, player: admin, surroundings:)
    assert_equal [ 0, "10halve" ], bidding_of(outcome, host).values_at("to_act", "melding")
    outcome = player_acts(table, :pas, player: host, surroundings:)

    assert_equal 4, outcome.messages.size
    outcome.messages.each do |message|
      view = message.payload["state"]["view"]
      # Halve is played (ticket 06): the melder calls the ace next.
      assert_equal [ "calling_ace", 1, nil ], [ *view.values_at("phase", "to_act"), view["result"] ]
      assert_equal({ "kind" => "melder", "melder" => 1, "melding" => "10halve", "went_with" => [], "reason" => nil, "dealer" => nil }, view["bidding"]["outcome"])
    end
    assert_equal %w[bid bid det_kan_jeg_selv bid det_kan_jeg_selv pas pas pas], bidding_of(outcome, erik)["history"].map { |entry| entry["action"] }
    assert_equal "1:9 2:10 1:selv 2:10halve 1:selv 2:pas 3:pas 0:pas", table.current_game.current_round.reload.actions
    assert_equal [ 1 ], table.current_game.seats_to_act
    assert_empty @scheduler.deals, "no redeal, and the runde goes on"
  end

  test "gå med on a sol-melding: the holder goes with, the challenger keeps the sol-melding" do
    table = started_table
    host, erik, frida, admin = @players

    player_acts(table, :bid, player: erik, melding: "9", surroundings:)
    outcome = player_acts(table, :bid, player: frida, melding: "sol", surroundings:)
    assert_equal [ true, true ], choices_of(outcome, erik).values_at("det_kan_jeg_selv", "gaa_med")

    outcome = player_acts(table, :gaa_med, player: erik, surroundings:)
    assert_equal [ "sol", 2, 3 ], bidding_of(outcome, admin).values_at("melding", "holder", "to_act")
    assert_equal [ 1 ], bidding_of(outcome, admin)["went_with"]
    assert choices_of(outcome, admin)["gaa_med"], "the next seat may go with too"

    player_acts(table, :pas, player: admin, surroundings:)
    outcome = player_acts(table, :pas, player: host, surroundings:)

    assert_equal({ "kind" => "melder", "melder" => 2, "melding" => "sol", "went_with" => [ 1 ], "reason" => nil, "dealer" => nil },
                 bidding_of(outcome, host)["outcome"])
  end

  test "gå med is only for sol-meldinger, and other illegal choices are answered to that seat only" do
    table = started_table
    _host, erik, frida, = @players

    assert_rejected :not_your_turn, player_acts(table, :pas, player: frida, surroundings:), frida
    assert_rejected :not_on_ladder, player_acts(table, :bid, player: erik, melding: "7", surroundings:), erik
    assert_rejected :not_on_ladder, player_acts(table, :bid, player: erik, melding: "spar", surroundings:), erik
    player_acts(table, :bid, player: erik, melding: "9", surroundings:)
    assert_rejected :not_sol_melding, player_acts(table, :gaa_med, player: frida, surroundings:), frida
    assert_rejected :not_higher, player_acts(table, :bid, player: frida, melding: "8vip", surroundings:), frida
    assert_rejected :nothing_to_take_over, player_acts(table, :det_kan_jeg_selv, player: frida, surroundings:), frida
    assert_equal "1:9", table.current_game.current_round.reload.actions
  end

  test "all pass: the runde is dealt again by the former forhånd, and it is still runde 1" do
    table = started_table
    host, erik, frida, admin = @players

    [ erik, frida, admin ].each { |player| player_acts(table, :pas, player:, surroundings:) }
    outcome = player_acts(table, :pas, player: host, surroundings:)

    view = state_of(outcome, frida)["view"]
    assert_equal [ "redeal", nil ], view.values_at("phase", "to_act")
    assert_equal({ "kind" => "redeal", "melder" => nil, "melding" => nil, "went_with" => [], "reason" => "all_passed", "dealer" => 1 }, view["bidding"]["outcome"])
    game = table.current_game
    assert_equal [ { game_id: game.id, number: 2, delay: Table::Playing::REDEAL_PAUSE } ], @scheduler.deals

    first_deal = game.current_round.deal
    dealt = table.next_runde(game_id: game.id, number: 2, surroundings: surroundings(seed: 9))

    round = Game.find(game.id).current_round
    assert_equal [ 2, 1, "" ], [ round.number, round.dealer, round.actions ]
    assert_not_equal first_deal, round.deal
    state = state_of(dealt, admin)
    assert_equal [ 1, 2, 2, 1 ], [ state["view"]["dealer"], state["view"]["forhand"], state["view"]["to_act"], state["runde"] ]
    assert_equal [ 2, 10 ], state.values_at("round_number", "runder")
    assert_equal "bidding", state["view"]["phase"]
  end

  test "a jernhånd is claimed out of turn before the first bid: the same kortgiver deals the runde again" do
    table = started_table(jernhaand_seat: 2)
    _host, erik, frida, admin = @players

    outcome = player_acts(table, :pas, player: erik, surroundings:)
    assert choices_of(outcome, frida)["jernhaand"]
    assert_not choices_of(outcome, admin)["jernhaand"]
    assert_rejected :no_jernhaand, player_acts(table, :claim_jernhaand, player: admin, surroundings:), admin

    outcome = player_acts(table, :claim_jernhaand, player: frida, surroundings:)

    assert_equal({ "kind" => "redeal", "melder" => nil, "melding" => nil, "went_with" => [], "reason" => "jernhaand", "dealer" => 0 },
                 bidding_of(outcome, erik)["outcome"])
    game = table.current_game
    table.next_runde(game_id: game.id, number: 2, surroundings:)
    round = Game.find(game.id).current_round
    assert_equal [ 2, 0 ], [ round.number, round.dealer ]
    assert_equal 1, EsmakkerSpil.engine_round(round, game.engine_rules).forhand, "the forhånd keeps the forhånd"
  end

  test "a jernhånd can no longer be claimed once someone has bid" do
    table = started_table(jernhaand_seat: 2)
    _host, erik, frida, = @players

    player_acts(table, :bid, player: erik, melding: "8", surroundings:)

    assert_rejected :bidding_started, player_acts(table, :claim_jernhaand, player: frida, surroundings:), frida
  end

  test "the tur-ur runs on the seat to bid, as at hjerterfri" do
    table = started_table
    _host, erik, frida, = @players
    seconds = ->(outcome) { state_of(outcome, frida)["seats"].map { |seat| seat["seconds_left"] } }

    @clock.advance(20)
    outcome = player_acts(table, :bid, player: erik, melding: "8", surroundings:)

    assert_equal [ nil, nil, TurnClock::LIMIT, nil ], seconds.call(outcome)
    assert_predicate @scheduler.ticks, :any?
  end

  test "a player who forlader on their turn: the bot that takes the seat melder 9 (Esmakker::Bot)" do
    table = started_table
    _host, erik, frida, = @players

    outcome = table.leave(user: erik, surroundings:)

    assert_equal "1:9", table.current_game.current_round.reload.actions
    assert_equal 2, bidding_of(outcome, frida)["to_act"]
  end

  private

  def surroundings(seed: 0) = Table::Surroundings.new(clock: @clock, scheduler: @scheduler, shuffler: Random.new(seed), random: Random.new(seed))

  # The stored es-makker bord with its spil started. With `jernhaand_seat`,
  # runde 1's deal gives that seat a jernhånd.
  def started_table(jernhaand_seat: nil)
    waiting = WaitingTable.set_up(user: @host, game: "esmakker", surroundings:).table
    @players.drop(1).each_with_index { |user, index| waiting.sit(user:, seat: index + 1, surroundings:) }
    table = waiting.reload.start(user: @host, surroundings:).table
    table.current_game.current_round.update!(deal: jernhaand_deal(jernhaand_seat).to_s) if jernhaand_seat
    Table.find(table.id)
  end

  def jernhaand_deal(seat)
    numbers = Esmakker::Card.deck.select { |card| !card.joker? && %w[2 3 4 5 6 7 8 9 T].include?(card.rank) }.first(13)
    rest = Esmakker::Card.deck - numbers
    Esmakker::Deal.new(hands: (0..3).map { |other| other == seat ? numbers : rest.shift(13) }, kitty: rest)
  end

  def message_for(outcome, user) = outcome.messages.find { |message| message.user_id == user.id }
  def state_of(outcome, user) = message_for(outcome, user).payload["state"]
  def bidding_of(outcome, user) = state_of(outcome, user)["view"]["bidding"]
  def choices_of(outcome, user) = state_of(outcome, user)["view"]["choices"]

  def assert_rejected(reason, outcome, user)
    message = outcome.messages.sole
    assert_equal [ "rejected", reason.to_s, user.id ], [ message.payload["type"], message.payload["reason"], message.user_id ]
  end
end
