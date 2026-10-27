require "test_helper"

# Es-makker bots at the bord (esmakker-bots ticket 01). Es-makker has no
# bots in the app (EsmakkerSpil.bots?; Anders: they do not work yet): no
# es-makker øvebord, no bot in an empty seat, and no bot takes over a
# player who forlader; the spil is afbrudt instead. The bord still plays
# the bots a stored es-makker bord holds (stored_esmakker_with_bots): they
# are players, woken by the bord's scheduler, acting through the bord's
# one way in (Table#act) with the first es-makker bot's choices
# (Esmakker::Bot). A whole spil plays to its end with the human playing
# simple legal moves.
class EsmakkerBotTableTest < ActiveSupport::TestCase
  setup do
    @user = users(:approved)
    @scheduler = FakeScheduler.new
  end

  test "there is no es-makker øvebord" do
    outcome = WaitingTable.set_up_practice(user: @user, game: "esmakker", surroundings:)

    assert_equal :no_bots, outcome.refusal
    assert_nil outcome.table
  end

  test "the vært may not put a bot in an es-makker bord's empty seat, at any level" do
    waiting = WaitingTable.set_up(user: @user, game: "esmakker", surroundings:).table

    Hjerterfri::Bot::LEVELS.each { |level| assert_equal :no_bots, waiting.add_bot(user: @user, seat: 1, level: level.to_s, surroundings:).refusal }
    assert waiting.reload.occupants.fetch(1).empty?
  end

  test "a player who forlader an es-makker spil: no bot takes over, the spil is afbrudt and the bord closes for everyone" do
    waiting = WaitingTable.set_up(user: @user, game: "esmakker", surroundings:).table
    others = [ users(:erik), users(:frida), users(:admin) ]
    others.each.with_index(1) { |user, seat| waiting.sit(user:, seat:, surroundings:) }
    table = waiting.start(user: @user, surroundings:).table.reload

    outcome = table.leave(user: users(:erik), surroundings:)

    game = Game.find(table.current_game.id)
    assert_equal [ true, users(:erik).id, [] ], [ game.abandoned?, game.forfeited_by_id, game.seat_log ]
    assert table.reload.closed?
    assert_not table.seating.occupants.any?(&:bot?)
    assert_equal [ @user, *others ].map(&:id).sort, outcome.messages.map(&:user_id).sort
    assert(outcome.messages.all? { |message| message.payload["type"] == "closed" })
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

  private

  def surroundings(seed: 0) = Table::Surroundings.new(scheduler: @scheduler, shuffler: Random.new(seed), random: Random.new(seed))

  def start_esmakker_practice(runder:) = stored_esmakker_with_bots([ @user ], runder:, surroundings:)

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
