require "test_helper"

# Es-makker bots at the bord (esmakker-bots ticket 01): an es-makker
# øvebord (one human, three bots) and an es-makker bord whose vært fills
# the empty seats with bots. The bots are players: woken by the bord's
# scheduler, they act through the bord's one way in (Table#act) with the
# first es-makker bot's choices (Esmakker::Bot), and their levels are
# stored like hjerterfri's (seats.bot_level, the spil's seats and
# seat_log). A whole spil plays to its end with the human playing simple
# legal moves.
class EsmakkerBotTableTest < ActiveSupport::TestCase
  setup do
    @user = users(:approved)
    @scheduler = FakeScheduler.new
  end

  test "an es-makker øvebord seats the user and three bots, plays es-makker and stores the bots' levels" do
    waiting = WaitingTable.set_up_practice(user: @user, game: "esmakker", surroundings:).table
    waiting.change_bot_level(user: @user, seat: 2, level: "svaer", surroundings:)

    assert_equal [ "esmakker", "practice", 10 ], [ waiting.game, waiting.reload.kind, waiting.reload.rules.runder ]
    table = waiting.start(user: @user, surroundings:).table.reload

    assert_equal [ "esmakker", "practice" ], [ table.game, table.kind ]
    assert_equal [ nil, "mellem", "svaer", "mellem" ], table.seats.order(:position).pluck(:bot_level)
    assert_equal [ nil, "mellem", "svaer", "mellem" ], table.current_game.seats.map { |seat| seat["level"] }
  end

  test "at an es-makker øvebord the player sets the number of runder; it stays a practice bord" do
    waiting = WaitingTable.set_up_practice(user: @user, game: "esmakker", surroundings:).table

    assert_nil waiting.change_settings(user: @user, rules: {}, runder: "5", surroundings:).refusal
    assert_equal [ "practice", 5 ], [ waiting.reload.kind, waiting.reload.rules.runder ]
  end

  test "a whole spil plays to its end: one human and three bots" do
    table = start_esmakker_practice(runder: 5)

    play_spil(table)

    game = Game.find(table.current_game.id)
    assert game.finished?
    assert_equal 5, game.engine_game.results.size
    assert_equal 0, game.final_scores.sum
    assert table.reload.closed?
  end

  test "the bots melder 9 when they may and pas otherwise, and never bank" do
    table = start_esmakker_practice(runder: 5)

    play_spil(table)

    Game.find(table.current_game.id).rounds.each do |row|
      bids = row.actions.split.map { |entry| entry.split(":", 2) }.take_while { |_seat, token| Esmakker::Round.bidding_intent?(Esmakker::Round.intent(token)) }
      bot_bids = bids.reject { |seat, _token| seat == "0" }.map(&:last)
      assert_equal [ "9" ], bot_bids.uniq - [ "pas" ], "runde #{row.number}: #{bids.inspect}"
      assert_operator bot_bids.count("9"), :<=, 1, "only the first may melde 9"
      assert_not_includes row.actions, "bank"
    end
  end

  test "the vært fills an es-makker bord's empty seats with bots and the spil starts" do
    waiting = WaitingTable.set_up(user: @user, game: "esmakker", surroundings:).table
    (1..3).each { |seat| assert_nil waiting.add_bot(user: @user, seat:, level: "let", surroundings:).refusal }

    outcome = waiting.start(user: @user, surroundings:)

    assert_nil outcome.refusal
    table = outcome.table.reload
    assert_equal [ nil, "let", "let", "let" ], table.seats.order(:position).pluck(:bot_level)
    assert_equal [ 1 ], @scheduler.turns.map { |turn| turn[:seat] }, "the forhånd bot is woken"
  end

  test "a bot that takes over a seat at an es-makker bord plays on as the first bot" do
    waiting = WaitingTable.set_up(user: @user, game: "esmakker", surroundings:).table
    waiting.sit(user: users(:erik), seat: 1, surroundings:)
    (2..3).each { |seat| waiting.add_bot(user: @user, seat:, surroundings:) }
    table = waiting.start(user: @user, surroundings:).table.reload

    table.leave(user: users(:erik), surroundings:)

    game = Game.find(table.current_game.id)
    assert_equal [ 1, "Bot 3", Table::Seating::TAKEOVER_LEVEL.to_s ], game.seat_log.last.values_at("seat", "to", "level")
    assert_equal "1:9", game.current_round.actions.split.first, "the forhånd's bot melder 9"
  end

  private

  def surroundings(seed: 0) = Table::Surroundings.new(scheduler: @scheduler, shuffler: Random.new(seed), random: Random.new(seed))

  def start_esmakker_practice(runder:)
    waiting = WaitingTable.set_up_practice(user: @user, game: "esmakker", surroundings:).table
    waiting.change_settings(user: @user, rules: {}, runder: runder.to_s, surroundings:)
    waiting.start(user: @user, surroundings:).table.reload
  end

  # Plays the spil out: the bots' scheduled turns run, the next runde is
  # dealt when due, and the human (seat 0) says pas in the meldingsrunde
  # and otherwise makes its first choice. Every step must be accepted.
  def play_spil(table)
    2_000.times do
      run_bot_turns
      game = Game.find(table.current_game.id)
      return unless game.in_progress?

      deal = @scheduler.deals.shift
      next table.next_runde(**deal.except(:delay), surroundings:) if deal

      view = game.engine_round.view_for(0)
      raise "stuck at #{view[:phase]}, #{view[:to_act]} to act" unless view[:to_act].zero?

      outcome = table.act(player: @user, intent: human_choice(view), surroundings:)
      raise "rejected: #{outcome.messages.first&.payload}" if outcome.messages.any? { |message| message.payload["type"] == "rejected" }
    end
    raise "the spil did not end"
  end

  def human_choice(view)
    choices = view[:choices]
    case view[:phase]
    when :bidding then Esmakker::Bidding::Pas.new
    when :choosing_trump then Esmakker::ChooseTrump.new(trump: Esmakker::Trump.parse(choices[:trumps].first))
    when :playing then Esmakker::PlayCard.new(card: Esmakker::Card.parse(view[:play][:legal_moves].first))
    else raise "the human has nothing to do at #{view[:phase]}"
    end
  end

  # Runs scheduled bot turns, oldest first, until none are left. A bot's
  # rejected intent is answered to nobody: the spil would stall with a bot
  # to act, which #play_spil reports.
  def run_bot_turns
    while (turn = @scheduler.turns.shift)
      Table::BotPlayer.wake(**turn, surroundings:)
    end
  end
end
