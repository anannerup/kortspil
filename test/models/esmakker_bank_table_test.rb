require "test_helper"

# Seam 2 for ticket 08: bank i bordet through the bord's actions, with a
# fake scheduler and clock. When the vip melder has exchanged with the
# kitty the bank window opens for the bord's seconds (Anders, 26 October
# 2026): a job is scheduled to close it, every seat gets the countdown, and
# the three non-melders are offered "Bank" alike. Banks within the window
# are taken; one after its time is refused; the first bank starts the
# window again for the melder; the second bank closes it at once; the job
# closes it otherwise, and a repeated or stale job does nothing.
#
# Seats: the vært (seat 0) deals runde 1, so erik (seat 1) is forhånd and
# the melder, then frida (2) and admin (3).
class EsmakkerBankTableTest < ActiveSupport::TestCase
  setup do
    @host = users(:approved)
    @players = [ @host, users(:erik), users(:frida), users(:admin) ]
    @erik = @players[1]
    @scheduler = FakeScheduler.new
    @clock = FakeClock.new
  end

  test "the melder laid away: the window opens for the bord's seconds, a job will close it, and the bank option looks the same to the three" do
    table = started_table
    outcome = name_trump(table)
    assert_equal "discarding", state_of(outcome, @erik)["view"]["phase"], "no window when trump is named"
    assert_empty @scheduler.bank_windows
    outcome = lay_away(table)

    assert_equal [ { game_id: table.current_game.id, number: 1, delay: 8.0 } ], @scheduler.bank_windows
    @players.each do |player|
      state = state_of(outcome, player)
      assert_equal [ "banking", true, [] ], [ state["view"]["phase"], *state["view"]["play"].values_at("bank_window", "banks") ]
      assert_equal [ 8, 8.0 ], state["bank_window"].values_at("seconds", "seconds_left")
    end
    others = @players - [ @erik ]
    assert_equal [ true ], others.map { |player| state_of(outcome, player)["view"]["choices"] }.uniq.map { |choices| choices["bank"] }
    assert_equal 1, others.map { |player| state_of(outcome, player)["view"]["choices"] }.uniq.size, "the esmakker's choices are the modspilleres'"
    assert_not state_of(outcome, @erik)["view"]["choices"]["bank"]
    assert_empty @scheduler.turns, "nobody is to act in the window"

    @clock.advance(3)
    table.connect(user: @host, surroundings:)
    assert_equal 5.0, @scheduler.bank_windows.last[:delay], "a reconnect schedules the rest of the window again"
  end

  test "a modspiller banks, the melder banks back: the window closes at once, ×4, and the job finds nothing to close" do
    table = started_table
    name_trump(table)
    lay_away(table)
    modspiller = modspillere(table).first

    assert_rejected :melder_banks_second, table.bank(player: @erik, surroundings:), @erik
    @clock.advance(2)
    outcome = table.bank(player: modspiller, surroundings:)
    @players.each do |player|
      state = state_of(outcome, player)
      assert_equal [ seat_of(table, modspiller) ], state["view"]["play"]["banks"]
      assert_equal 8.0, state["bank_window"]["seconds_left"], "the window starts again for the melder"
    end
    assert state_of(outcome, @erik)["view"]["choices"]["bank"]
    esmakker = esmakker_of(table)
    assert_rejected :only_melder_banks_again, table.bank(player: esmakker, surroundings:), esmakker

    outcome = table.bank(player: @erik, surroundings:)
    @players.each do |player|
      state = state_of(outcome, player)
      assert_equal [ "playing", false, nil ], [ state["view"]["phase"], state["view"]["play"]["bank_window"], state["bank_window"] ]
    end
    assert_nil table.current_game.reload.bank_closes_at
    assert_empty close_bank_window(table).messages

    result = finish(table)
    assert_equal 2, result["banks"]
    assert_equal expected_points(result, factor: 2 * 4), result["points"]
  end

  test "nobody banks: the window closes when its time runs out, the melder leads, a late bank is refused, a repeat job does nothing" do
    table = started_table
    name_trump(table)
    lay_away(table)
    @clock.advance(8)

    late = modspillere(table).first
    assert_rejected :bank_window_closed, table.bank(player: late, surroundings:), late
    outcome = close_bank_window(table)
    @players.each { |player| assert_equal [ "playing", nil ], [ state_of(outcome, player)["view"]["phase"], state_of(outcome, player)["bank_window"] ] }
    assert_equal [ 13, 1 ], [ state_of(outcome, @erik)["view"]["hand"].size, state_of(outcome, @erik)["view"]["to_act"] ]
    assert_rejected :not_now, table.bank(player: late, surroundings:), late
    assert_empty close_bank_window(table).messages, "a repeat changes nothing"

    result = finish(table)
    assert_equal 0, result["banks"]
    assert_equal expected_points(result, factor: 2), result["points"]
    assert_includes engine_round(table).actions_string.split, "1:bankslut"
  end

  test "one bank and the time runs out: ×2 on the vip card" do
    table = started_table
    name_trump(table)
    lay_away(table)
    @clock.advance(5)
    table.bank(player: modspillere(table).last, surroundings:)
    assert_equal 8.0, @scheduler.bank_windows.last[:delay], "a whole window for the melder"
    @clock.advance(3)
    outcome = table.close_bank_window(**@scheduler.bank_windows.first.except(:delay), surroundings:)
    assert_empty outcome.messages, "the first window's job finds the time not out yet"
    assert_equal [ :banking, 5.0 ], [ engine_round(table).phase, @scheduler.bank_windows.last[:delay] ], "and schedules the rest"
    @clock.advance(5)
    close_bank_window(table)

    result = finish(table)
    assert_equal 1, result["banks"]
    assert_equal expected_points(result, factor: 2 * 2), result["points"]
    assert_equal 1, state_of(table.connect(user: @host, surroundings:), @host)["score"]["results"].last["banks"], "the score sheet shows the banks"
  end

  test "the esmakker may bank first at the standard bord" do
    table = started_table
    name_trump(table)
    lay_away(table)
    esmakker = esmakker_of(table)
    assert_equal [ seat_of(table, esmakker) ], state_of(table.bank(player: esmakker, surroundings:), @host)["view"]["play"]["banks"]
  end

  test "where the bord forbids the esmakker to bank first, she is offered Bank like the others, and her press is refused to her alone" do
    table = started_table(rules: { esmakker_banks_first: "0", bank_window: "5" })
    name_trump(table)
    outcome = lay_away(table)
    assert_equal 5.0, @scheduler.bank_windows.last[:delay]
    esmakker = esmakker_of(table)
    assert state_of(outcome, esmakker)["view"]["choices"]["bank"], "she is offered Bank like the others"
    assert_rejected :esmakker_banks_first_not_allowed, table.bank(player: esmakker, surroundings:), esmakker
    assert_empty engine_round(table).play.banks
  end

  test "a bot in the melder's seat never banks: it waits out the window and leads" do
    table = started_table
    name_trump(table)
    lay_away(table)
    table.bank(player: modspillere(table).first, surroundings:)
    table.leave(user: @erik, surroundings:)

    assert_empty @scheduler.turns.select { |turn| turn[:seat] == 1 }, "no bot turn while the window is open"
    @clock.advance(8)
    close_bank_window(table)
    Table::BotPlayer.wake(**@scheduler.turns.last, surroundings:)
    assert_equal [ :playing, [ seat_of(table, modspillere(table).first) ] ], [ engine_round(table).phase, engine_round(table).play.banks ]
  end

  private

  def surroundings(seed: @seed || 0) = Table::Surroundings.new(clock: @clock, scheduler: @scheduler, shuffler: Random.new(seed), random: Random.new(seed))

  # The stored es-makker bord with its spil started, its rules from the
  # settings form (`rules`).
  def started_table(seed: 0, rules: nil)
    @seed = seed
    waiting = WaitingTable.set_up(user: @host, game: "esmakker", surroundings:).table
    waiting.change_settings(user: @host, rules:, kind: "open", runder: "10", surroundings:) if rules
    @players.drop(1).each_with_index { |user, index| waiting.sit(user:, seat: index + 1, surroundings:) }
    Table.find(waiting.reload.start(user: @host, surroundings:).table.id)
  end

  # Erik bids 8 vip, calls an ace another seat holds, turns the first card
  # and takes it: he holds the kitty.
  def name_trump(table)
    table.bid(player: @erik, melding: "8vip", surroundings:)
    [ 2, 3, 0 ].each { |seat| table.pas(player: @players[seat], surroundings:) }
    deal = engine_round(table).deal
    ace = engine_view(table, 1)[:choices][:aces].find { |suit| Esmakker::Seats::ALL.any? { |seat| deal.hand(seat).include?(Esmakker::Card.new(rank: "A", suit:)) } }
    table.call_ace(player: @erik, suit: ace, surroundings:)
    table.turn_card(player: @erik, surroundings:)
    table.accept_trump(player: @erik, surroundings:)
  end

  # Erik lays the kitty back: the bank window opens.
  def lay_away(table) = table.discard(player: @erik, cards: engine_round(table).deal.kitty.map(&:to_s), surroundings:)

  def esmakker_of(table) = @players[engine_round(table).play.esmakker]
  def modspillere(table) = @players - [ @erik, esmakker_of(table) ]

  # The window's job runs (as BankWindowJob would).
  def close_bank_window(table) = table.close_bank_window(**@scheduler.bank_windows.last.except(:delay), surroundings:)

  # The runde is played out; its result.
  def finish(table)
    outcome = nil
    until (round = engine_round(table)).complete?
      outcome = table.play(player: @players[round.to_act], card: engine_view(table, round.to_act)[:play][:legal_moves].first, surroundings:)
    end
    state_of(outcome, @host)["view"]["result"]
  end

  # The runde points two against two (a selvmakker with each of the three);
  # `factor` is vip's card and the banks, and clubs or trumfløs as trump
  # doubles once more.
  def expected_points(result, factor:)
    factor *= 2 if %w[C trumfloes].include?(result["trump"])
    number = result["melding"].to_i
    over = result["stik"] - number
    amount = (over.negative? ? -over : 1 + over) * factor
    sign = result["gik_hjem"] ? 1 : -1
    side = [ result["melder"], result["esmakker"] ].compact
    (0..3).map { |seat| (side.include?(seat) ? sign : -sign) * amount * (result["selvmakker"] && seat == result["melder"] ? 3 : 1) }
  end

  def seat_of(table, user) = table.seating.seat_of(user)
  def engine_round(table) = Game.find(table.current_game.id).engine_round
  def engine_view(table, seat) = engine_round(table).view_for(seat)
  def message_for(outcome, user) = outcome.messages.find { |message| message.user_id == user.id }
  def state_of(outcome, user) = message_for(outcome, user).payload["state"]

  def assert_rejected(reason, outcome, user)
    message = outcome.messages.sole
    assert_equal [ "rejected", reason.to_s, user.id ], [ message.payload["type"], message.payload["reason"], message.user_id ]
  end
end
