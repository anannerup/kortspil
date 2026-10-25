require "test_helper"

# Seam 2: the bord's actions in a spil (Table::Playing) at a practice
# table, driven through them and asserted on the messages they return and
# the rows they store.
class TablePlayingTest < ActiveSupport::TestCase
  # Seat 0 holds every club, so it leads and wins all 13 stik.
  BY_SUIT = %w[C D S H].map { |suit| Hjerterfri::Card::RANKS.map { |rank| "#{rank}#{suit}" } }
  # Played out, seats 1 and 3 tie for the lowest total: [25, 0, 1, 0].
  SPOILED_MOON = [
    %w[2C 3C 4C 5C 6C 7C 8C 9C TC JC QC KC AS],
    BY_SUIT[1],
    %w[AC 2S 3S 4S 5S 6S 7S 8S 9S TS JS QS KS],
    BY_SUIT[3]
  ]

  setup do
    @user = users(:approved)
    @scheduler = FakeScheduler.new
  end

  # --- Starting and passing (ticket 07) ---

  test "a practice table seats the user and three bots and waits, with nothing stored yet" do
    outcome = nil
    assert_no_difference %w[ Table.count Seat.count Game.count ] do
      outcome = WaitingTable.set_up_practice(user: @user, rules: Hjerterfri::Rules.new(end_score: 50), surroundings: surroundings(seed: 0))
    end

    table = outcome.table
    assert table.practice?
    assert table.waiting?
    assert_empty outcome.messages
    assert_equal @user, table.host
    assert_equal [ @user.username, "Bot 1", "Bot 2", "Bot 3" ], table.seating.occupants.map(&:name)
    assert_empty @scheduler.turns
  end

  test "the practice player changes the rules at the table; the table stays a practice table" do
    table = WaitingTable.set_up_practice(user: @user, surroundings:).table
    rules = Hjerterfri::Rules.new(end_score: 30, shooters_choice: true)

    outcome = table.change_settings(user: @user, rules:, kind: "open", surroundings:)

    assert_not outcome.refused?
    assert table.reload.practice?
    assert_equal rules, table.reload.rules.game
  end

  test "a practice table keeps its three bots" do
    table = WaitingTable.set_up_practice(user: @user, surroundings:).table

    assert_equal :practice_seats, table.remove_bot(user: @user, seat: 1, surroundings:).refusal
    assert_equal :practice_seats, table.kick(user: @user, seat: 1, surroundings:).refusal
    assert table.seating.full?
  end

  test "starting a practice table deals runde 1 passing left" do
    table = WaitingTable.set_up_practice(user: @user, surroundings: surroundings(seed: 0)).table
    outcome = table.start(user: @user, surroundings: surroundings(seed: 0))

    table = outcome.table
    game = table.current_game
    assert table.reload.playing?
    assert table.practice?
    assert_equal table.seating.snapshot, game.seats, "the spil stores who sat where at the start"
    record = game.current_round
    assert_equal [ 1, "left", "" ], [ record.number, record.pass_direction, record.passes ]
    assert_equal 52, record.deal.split.size

    state = outcome.messages.sole.payload["state"]
    assert_equal 0, outcome.messages.sole.seat
    assert_equal "passing", state["view"]["phase"]
    assert_equal "left", state["view"]["pass_direction"]
    assert_nil state["view"]["to_act"]
    assert_equal 13, state["view"]["hand"].size
    assert_equal [ @user.username, "Bot 1", "Bot 2", "Bot 3" ], state["seats"].map { |seat| seat["name"] }
    assert_equal [ 1, 2, 3 ], @scheduler.turns.map { |turn| turn[:seat] }
    assert @scheduler.turns.all? { |turn| turn[:version] == spil(table).version }
  end

  test "a pass is stored at once but nobody sees incoming cards until all four have passed" do
    table = start_practice(seed: 0)
    dealt = hand_of(table, 0)
    cards = dealt.last(3)
    before = spil(table).version

    outcome = table.pass(user: @user, cards:, surroundings:)

    assert_equal cards + [ "--" ] * 9, table.current_game.current_round.reload.passes.split
    state = outcome.messages.sole.payload["state"]
    view = state["view"]
    assert_equal "passing", view["phase"]
    assert_equal [ 0 ], view["passed_seats"]
    assert_equal cards.sort, view["own_pass"].sort
    assert_empty view["received_cards"]
    assert_equal dealt.sort, view["hand"].sort
    assert_operator state["version"], :>, before
    assert_equal spil(table).version, state["version"]
  end

  test "bots pass their own cards; others' passes stay hidden until the last one is in" do
    table = start_practice(seed: 0)
    first_bot, *other_bots = @scheduler.turns.shift(3)

    view = Game.find(first_bot[:game_id]).table.bot_turn(**first_bot, surroundings:).messages.sole.payload["state"]["view"]
    assert_equal [ first_bot[:seat] ], view["passed_seats"]
    assert_empty view["received_cards"]
    assert_empty card_codes_in(view) - hand_of(table, 0), "no bot's pass is shown"

    other_bots.each { |turn| Game.find(turn[:game_id]).table.bot_turn(**turn, surroundings:) }
    table.pass(user: @user, cards: hand_of(table, 0).last(3), surroundings:)

    passes = table.current_game.current_round.reload.passes.split.each_slice(3).to_a
    assert passes.none? { |slot| slot.include?("--") }
    passes.each_with_index { |slot, seat| assert_empty slot - hand_of(table, seat), "seat #{seat} passed its own cards" }
    view = connect_state(table)["view"]
    assert_equal "playing", view["phase"]
    assert_equal passes[3].sort, view["received_cards"].sort, "left: seat 0 receives from seat 3"
    assert_equal (hand_of(table, 0) - passes[0] + passes[3]).sort, view["hand"].sort
  end

  test "after the pass the holder of 2♣ leads" do
    table = start_practice(seed: seed_where_human_leads)
    pass_runde(table)

    assert_equal 0, connect_state(table)["view"]["to_act"]
    assert_empty @scheduler.turns

    table.leave(user: @user, surroundings:)
    table = start_practice(seed: seed_where_bot_leads)
    pass_runde(table)
    leader = connect_state(table)["view"]["to_act"]
    assert_operator leader, :>, 0
    assert_equal({ game_id: table.current_game.id, seat: leader, version: spil(table).version }, @scheduler.turns.sole.except(:delay))
  end

  test "an illegal pass is rejected to that seat only and nothing is stored" do
    table = start_practice(seed: 0)
    hand = hand_of(table, 0)
    foreign = hand_of(table, 1).first

    assert_rejected "wrong_card_count", table.pass(user: @user, cards: hand.first(2), surroundings:)
    assert_rejected "card_not_in_hand", table.pass(user: @user, cards: [ *hand.first(2), foreign ], surroundings:)
    assert_rejected "duplicate_cards", table.pass(user: @user, cards: [ hand[0], hand[0], hand[1] ], surroundings:)
    assert_rejected "passing_not_complete", table.play(user: @user, card: hand.first, surroundings:)
    assert_equal "", table.current_game.current_round.reload.passes

    table.pass(user: @user, cards: hand.last(3), surroundings:)
    outcome = table.pass(user: @user, cards: hand.first(3), surroundings:)
    assert_equal({ "type" => "rejected", "reason" => "already_passed", "cards" => hand.first(3) }, outcome.messages.sole.payload)
  end

  # --- Playing (ticket 06, now after the pass) ---

  test "a legal play is stored and the human gets the new state" do
    table = start_practice(seed: seed_where_human_leads)
    pass_runde(table)

    outcome = table.play(user: @user, card: "2C", surroundings:)

    assert_equal "2C", table.current_game.current_round.reload.plays
    state = outcome.messages.sole.payload["state"]
    assert_equal [ { "seat" => 0, "card" => "2C" } ], state["view"]["current_trick"]
    assert_equal spil(table).version, state["version"]
    assert_equal({ game_id: table.current_game.id, seat: 1, version: state["version"] }, @scheduler.turns.last.except(:delay))
  end

  test "an illegal play is rejected to that seat only and nothing is stored" do
    table = start_practice(seed: seed_where_human_leads)
    pass_runde(table)
    other_card = (connect_state(table)["view"]["hand"] - [ "2C" ]).first

    outcome = table.play(user: @user, card: other_card, surroundings:)

    assert_equal({ "type" => "rejected", "reason" => "must_lead_two_of_clubs", "card" => other_card }, outcome.messages.sole.payload)
    assert_equal @user.id, outcome.messages.sole.user_id
    assert_equal "", table.current_game.current_round.reload.plays
    assert_empty @scheduler.turns
  end

  test "a user who does not sit at the table gets no messages and changes nothing" do
    table = start_practice(seed: 0)
    stranger = users(:admin)

    assert_empty table.pass(user: stranger, cards: hand_of(table, 0).last(3), surroundings:).messages
    assert_empty table.play(user: stranger, card: "2C", surroundings:).messages
    assert_empty table.deal_next_runde(user: stranger, surroundings:).messages
    assert_empty table.play_again(user: stranger, surroundings:).messages
    assert_empty table.leave(user: stranger, surroundings:).messages
    assert_equal "", table.current_game.current_round.reload.passes
    assert table.reload.playing?
    assert table.current_game.reload.in_progress?
  end

  test "a stale bot turn does nothing" do
    table = start_practice(seed: seed_where_bot_leads)
    pass_runde(table)
    turn = @scheduler.turns.first
    run_bot_turns
    plays = table.current_game.current_round.reload.plays

    assert_empty Game.find(turn[:game_id]).table.bot_turn(**turn, surroundings:).messages
    assert_equal plays, table.current_game.current_round.reload.plays
  end

  test "connecting while bots are to act schedules their turns again" do
    table = start_practice(seed: 0)
    scheduler = FakeScheduler.new

    table.connect(user: @user, surroundings: Table::Surroundings.new(scheduler:))

    assert_equal @scheduler.turns.map { |turn| turn.except(:delay) }, scheduler.turns.map { |turn| turn.except(:delay) }
  end

  test "messages only ever reveal the seat's own cards, cards received once all have passed, and cards played" do
    table = start_practice(seed: 0)
    messages = []

    play_runde(table) { |outcome| messages.concat(outcome.messages) }

    record = table.current_game.current_round.reload
    received = record.passes.split.each_slice(3).to_a.fetch(3)
    plays = record.plays.split
    assert messages.all? { |message| message.seat.zero? && message.user_id == @user.id }
    messages.each do |message|
      view = message.payload["state"]["view"]
      allowed = hand_of(table, 0) + plays.first(played_count(view))
      allowed += received if view["passed_seats"].size == 4
      assert_empty card_codes_in(message.payload) - allowed
    end
  end

  # --- Live points and the score sheet (ticket 08) ---

  test "the state holds the points each seat has taken so far, from the completed stik" do
    table = start_practice(seed: 0)
    states = []

    final = play_runde(table) { |outcome| outcome.messages.each { |message| states << message.payload["state"] } }

    plays = table.current_game.current_round.reload.plays.split
    states.each do |state|
      played = played_count(state["view"])
      taken = plays.first(played - (played % 4)).sum { |code| Hjerterfri::Card.parse(code).points }
      assert_equal taken, state["points_taken"].sum
    end
    assert_operator states.map { |state| state["points_taken"].sum }.uniq.size, :>, 1, "the points change during the runde"
    assert_equal 26, final["points_taken"].sum
  end

  test "a completed runde is in the score sheet and the next runde is scheduled, then dealt passing right" do
    table = start_practice(seed: 0)

    final = play_runde(table)

    game = table.current_game.reload
    points = final["view"]["points"]
    assert_includes [ 26, 78 ], points.sum
    assert game.in_progress?
    assert table.reload.playing?
    expected_score = {
      "end_score" => 100,
      "rows" => [ { "number" => 1, "pass_direction" => "left", "points" => points, "totals" => points } ],
      "totals" => points,
      "leaders" => points.each_index.select { |seat| points[seat] == points.min },
      "winners" => []
    }
    assert_equal expected_score, final["score"]
    deal = @scheduler.deals.sole
    assert_equal({ game_id: game.id, number: 2, delay: Table::RESULT_PAUSE }, deal)

    state = next_runde(deal.except(:delay)).messages.sole.payload["state"]

    assert_equal [ 2, "passing", "right" ], [ state["round_number"], state["view"]["phase"], state["view"]["pass_direction"] ]
    assert_equal [ 0, 0, 0, 0 ], state["points_taken"]
    assert_equal points, state["score"]["totals"]
    assert_equal [ 1, 2 ], game.rounds.reload.map(&:number)
    assert_operator state["version"], :>, final["version"]
    assert_empty next_runde(deal.except(:delay)).messages, "a repeated deal does nothing"
  end

  test "the human can deal the next runde without waiting, but not before the runde is complete" do
    table = start_practice(seed: 0)
    assert_empty table.deal_next_runde(user: @user, surroundings:).messages

    play_runde(table)
    state = table.deal_next_runde(user: @user, surroundings:).messages.sole.payload["state"]

    assert_equal 2, state["round_number"]
    assert_empty next_runde(@scheduler.deals.sole.except(:delay)).messages, "the scheduled deal is then stale"
  end

  test "pass directions cycle left, right, across, none and repeat, one rounds row per runde" do
    table = start_practice(seed: 0, rules: Hjerterfri::Rules.new(end_score: 1000))

    5.times do
      play_runde(table)
      next_runde(@scheduler.deals.shift.except(:delay))
    end

    records = table.current_game.rounds.reload
    assert_equal [ 1, 2, 3, 4, 5, 6 ], records.map(&:number)
    assert_equal %w[left right across none left right], records.map(&:pass_direction)
    assert_equal "", records[3].passes, "runde 4 has no pass"
    assert records.first(5).all? { |record| record.plays.split.size == 52 }
    rows = connect_state(table)["score"]["rows"]
    assert_equal [ [ 1, "left" ], [ 2, "right" ], [ 3, "across" ], [ 4, "none" ], [ 5, "left" ] ],
      rows.map { |row| [ row["number"], row["pass_direction"] ] }
    assert_equal rows.last["totals"], connect_state(table)["score"]["totals"]
  end

  test "a runde without passing starts in play with the 2♣ holder to act" do
    table = start_practice(seed: 0, rules: Hjerterfri::Rules.new(end_score: 1000))
    3.times do
      play_runde(table)
      next_runde(@scheduler.deals.shift.except(:delay))
    end

    state = connect_state(table)
    assert_equal [ 4, "playing", "none" ], [ state["round_number"], state["view"]["phase"], state["view"]["pass_direction"] ]
    assert_includes state["view"]["hand"], "2C" if state["view"]["to_act"].zero?
  end

  test "the spil ends at the end score: finished with its final scores, winners shown, no further runde" do
    table = start_practice(seed: 0, rules: Hjerterfri::Rules.new(end_score: 1))

    final = play_runde(table)

    game = table.current_game.reload
    assert game.finished?
    assert_equal final["view"]["points"], game.final_scores
    assert_equal "finished", final["status"]
    totals = final["score"]["totals"]
    assert_equal totals.each_index.select { |seat| totals[seat] == totals.min } & [ 0 ], final["score"]["winners"], "only the human can win"
    assert_empty @scheduler.deals
    assert table.reload.playing?, "the practice table stays open for Spil igen"
    assert_empty table.play(user: @user, card: "2C", surroundings:).messages
  end

  test "bots tied for the lowest total lead but do not win: no vinder" do
    table = start_practice(seed: 0, rules: Hjerterfri::Rules.new(end_score: 25))
    finish_with_deal(table, SPOILED_MOON)

    state = connect_state(table)
    assert_equal [ 25, 0, 1, 0 ], state["score"]["totals"]
    assert_equal [], state["score"]["winners"]
    assert_empty table.current_game.reload.winner_ids
    assert_equal [ 1, 3 ], state["score"]["leaders"]
    assert table.current_game.reload.finished?
    assert_equal [ 25, 0, 1, 0 ], table.current_game.final_scores
  end

  test "the moon shows in the runde points and the totals" do
    table = start_practice(seed: 0, rules: Hjerterfri::Rules.new(end_score: 26))
    finish_with_deal(table, BY_SUIT)

    state = connect_state(table)
    assert_equal 0, state["view"]["moon_shooter"]
    assert_equal [ 26, 0, 0, 0 ], state["points_taken"]
    assert_equal [ 0, 26, 26, 26 ], state["view"]["points"]
    assert_equal [ 0 ], state["score"]["winners"]
  end

  test "the table keeps the rules it was started with, and they are locked once dealt" do
    rules = Hjerterfri::Rules.new(end_score: 50, jack_of_diamonds_minus_ten: true, shooters_choice: true)
    table = start_practice(seed: 0, rules:)

    assert_equal rules, table.reload.rules.game
    assert_equal rules, table.current_game.engine_rules
    assert_equal rules.to_h.as_json, connect_state(table)["rules"]
    refute table.update(rules: Hjerterfri::Rules.standard.to_h)
    assert_includes table.errors[:rules], "kan ikke ændres, når spillet er startet"
  end

  test "under shooter's choice, a human moon shooter chooses before the next runde" do
    table = start_practice(seed: 0, rules: Hjerterfri::Rules.new(shooters_choice: true))
    finish_with_deal(table, BY_SUIT)

    state = connect_state(table)
    assert_equal [ "choosing_moon", 0, 0 ], state["view"].values_at("phase", "to_act", "moon_shooter")
    assert_empty state["view"]["points"]
    assert_empty @scheduler.deals
    assert_empty @scheduler.turns

    assert_rejected "unknown_moon_choice", table.choose_moon(user: @user, option: "both", surroundings:)
    outcome = table.choose_moon(user: @user, option: "subtract_from_self", surroundings:)

    state = outcome.messages.sole.payload["state"]
    assert_equal [ "complete", "subtract_from_self" ], state["view"].values_at("phase", "moon_choice")
    assert_equal [ -26, 0, 0, 0 ], state["view"]["points"]
    assert_equal [ -26, 0, 0, 0 ], state["score"]["totals"]
    assert_equal "subtract_from_self", table.current_game.current_round.reload.moon_choice
    assert_equal [ 2 ], @scheduler.deals.map { |deal| deal[:number] }
    assert_equal state, connect_state(table)
  end

  test "under shooter's choice, a bot moon shooter chooses on its turn" do
    table = start_practice(seed: 0, rules: Hjerterfri::Rules.new(shooters_choice: true))
    finish_with_deal(table, BY_SUIT.rotate(-2))

    assert_equal [ 2 ], @scheduler.turns.map { |turn| turn[:seat] }
    run_bot_turns

    state = connect_state(table)
    assert_equal [ "complete", "add_to_others" ], state["view"].values_at("phase", "moon_choice")
    assert_equal [ 26, 26, 0, 26 ], state["view"]["points"]
  end

  test "Spil igen starts a new spil with the same seats and rules once the spil is finished" do
    rules = Hjerterfri::Rules.new(end_score: 1)
    table = start_practice(seed: 0, rules:)
    assert_empty table.play_again(user: @user, surroundings:).messages, "not while the spil is in progress"
    play_runde(table)
    finished = table.current_game

    outcome = table.play_again(user: @user, surroundings:)

    game = table.reload.current_game
    assert_not_equal finished, game
    assert game.in_progress?
    assert_equal finished.seats, game.seats
    assert_equal rules.to_h.as_json, game.rules
    state = outcome.messages.sole.payload["state"]
    assert_equal [ game.id, 1, "passing", "left" ], [ state["game_id"], state["round_number"], state["view"]["phase"], state["view"]["pass_direction"] ]
    assert_equal [], state["score"]["rows"]
    assert_equal [ 1, 2, 3 ], @scheduler.turns.map { |turn| turn[:seat] }
    assert_empty table.play_again(user: @user, surroundings:).messages, "a second click does nothing"
    assert_equal 2, table.games.count
  end

  # --- Leaving ---

  test "leaving mid-spil forfeits it: abandoned with the scores so far, the leaver recorded, the table closed" do
    table = start_practice(seed: 0)
    play_runde(table)
    next_runde(@scheduler.deals.shift.except(:delay))
    totals = connect_state(table)["score"]["totals"]
    pending = @scheduler.turns.dup

    outcome = table.leave(user: @user, surroundings:)

    assert_equal [ { "type" => "closed" } ], outcome.messages.map(&:payload)
    game = table.current_game.reload
    assert game.abandoned?
    assert_equal @user, game.forfeited_by
    assert_equal totals, game.final_scores
    assert table.reload.closed?
    assert_equal 3, pending.size
    pending.each { |turn| assert_empty Game.find(turn[:game_id]).table.bot_turn(**turn, surroundings:).messages }
    assert_equal "", game.current_round.reload.passes, "a pending bot turn changes nothing"
    assert_empty connect(table).messages
    assert_empty table.leave(user: @user, surroundings:).messages
  end

  test "leaving after the spil is finished closes the table and keeps the result" do
    table = start_practice(seed: 0, rules: Hjerterfri::Rules.new(end_score: 1))
    play_runde(table)

    table.leave(user: @user, surroundings:)

    game = table.current_game.reload
    assert game.finished?
    assert_nil game.forfeited_by
    assert table.reload.closed?
  end

  private

  def surroundings(seed: 0) = Table::Surroundings.new(scheduler: @scheduler, shuffler: Random.new(seed), random: Random.new(seed))

  def start_practice(seed:, rules: Hjerterfri::Rules.standard) = started_practice(@user, surroundings: surroundings(seed:), rules:)

  # The state for seat 0 as a reconnect builds it, from the database; what
  # that reconnect schedules is not kept.
  def connect(table) = Table.find(table.id).connect(user: @user, surroundings: Table::Surroundings.new(scheduler: FakeScheduler.new))
  def connect_state(table) = connect(table).messages.sole.payload["state"]

  def spil(table) = table.current_game

  def next_runde(deal) = Game.find(deal[:game_id]).table.next_runde(**deal, surroundings:)

  # Cards played so far in the runde, from what the seat can see: every
  # card not in a hand.
  def played_count(view) = 52 - view["hand"].size - view["card_counts"].values.sum

  def hand_of(table, seat) = table.current_game.current_round.deal.split.each_slice(13).to_a.fetch(seat)

  # The human passes its three highest cards, then the bots pass through
  # their scheduled turns. Bots' later plays stay scheduled.
  def pass_runde(table)
    table.pass(user: @user, cards: connect_state(table)["view"]["hand"].last(3), surroundings:)
    @scheduler.turns.shift(3).each { |turn| Game.find(turn[:game_id]).table.bot_turn(**turn, surroundings:) }
  end

  def seed_where_human_leads = seed_where(&:zero?)
  def seed_where_bot_leads = seed_where(&:positive?)

  # A deal seed for which the 2♣ holder after runde 1's pass satisfies the
  # block, given the human's pass in #pass_runde and the bots' passes.
  def seed_where
    bot = Hjerterfri::Bot.new
    (0..).find do |seed|
      dealt = Hjerterfri::Round.new(rules: Hjerterfri::Rules.standard, deal: Hjerterfri::Deal.shuffled(shuffler: Random.new(seed)), pass_direction: :left)
      passed = (0..3).reduce(dealt) do |round, seat|
        hand = round.view_for(seat)[:hand]
        round.apply(seat, Hjerterfri::Pass.new(cards: seat.zero? ? hand.last(3) : bot.choose_pass(hand))).round
      end
      yield passed.to_act
    end
  end

  # Runs scheduled bot turns, oldest first, until none are left. Returns
  # the messages they produced.
  def run_bot_turns
    messages = []
    while (turn = @scheduler.turns.shift)
      outcome = Game.find(turn[:game_id]).table.bot_turn(**turn, surroundings:)
      yield outcome if block_given?
      messages.concat(outcome.messages)
    end
    messages
  end

  # Plays the current runde out: the human passes its three highest cards
  # and plays its first legal card; bots run in between. Returns the state
  # at the end of the runde.
  def play_runde(table, &observe)
    200.times do
      run_bot_turns(&observe)
      state = connect_state(table)
      view = state["view"]
      return state if view["phase"] == "complete"

      outcome =
        if view["phase"] == "passing" then table.pass(user: @user, cards: view["hand"].last(3), surroundings:)
        else table.play(user: @user, card: view["legal_moves"].first, surroundings:)
        end
      raise "rejected: #{outcome.messages.sole.payload}" if outcome.messages.sole.payload["type"] == "rejected"

      observe&.call(outcome)
    end
    raise "the runde did not end"
  end

  # Replaces runde 1 with a crafted deal (no pass) played out but for its
  # last card, then plays that card through the table so the runde is scored.
  def finish_with_deal(table, hands)
    round = Hjerterfri::Round.from_strings(rules: table.current_game.engine_rules, deal: hands.flatten.join(" "), plays: "")
    round = round.apply(round.to_act, Hjerterfri::Play.new(card: round.legal_moves(round.to_act).first)).round while round.plays.size < 51
    table.current_game.current_round.update!(pass_direction: "none", deal: round.deal_string, passes: "", plays: round.plays_string)
    @scheduler.turns.clear

    seat = round.to_act
    if seat.zero?
      table.play(user: @user, card: round.legal_moves(seat).sole, surroundings:)
    else
      table.bot_turn(game_id: table.current_game.id, seat:, version: spil(table).version, surroundings:)
    end
  end

  def assert_rejected(reason, outcome)
    assert_equal [ "rejected", reason ], outcome.messages.sole.payload.values_at("type", "reason")
  end

  def card_codes_in(payload)
    payload.to_json.scan(/"([2-9TJQKA][CDHS])"/).flatten.uniq
  end
end
