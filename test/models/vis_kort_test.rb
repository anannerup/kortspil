require "test_helper"

# "Vis kort" (esmakker-bots ticket 02, docs/bots/esmakker-strategy.md §5):
# an admin alone with bots switches it on and their state carries the bots'
# hands and each bot's latest thought, at hjerterfri and es-makker. Never to
# a player who is no admin, never at a bord with another human (not even
# when the switch was left on and a human sat down at the next spil's
# bord), and it never changes what the bots do.
class VisKortTest < ActiveSupport::TestCase
  setup do
    @admin = users(:admin)
    @scheduler = FakeScheduler.new
  end

  test "hjerterfri øvebord: the admin switches it on and sees the bots' hands, then each bot's pass and the rule behind it" do
    table = start_practice(@admin, game: "hjerterfri")

    outcome = table.switch_vis_kort(user: @admin, on: true, surroundings:)

    assert outcome.accepted?
    shown = outcome.messages.sole.payload["state"]["vis_kort"]
    game = table.current_game
    assert shown["on"]
    assert_equal [ 1, 2, 3 ], shown["bots"].map { |bot| bot["seat"] }
    assert_equal (1..3).map { |seat| game.engine_round.view_for(seat)[:hand] }, shown["bots"].map { |bot| bot["hand"] }
    assert_equal [ nil, nil, nil ], shown["bots"].map { |bot| bot["thought"] }

    run_bot_turns

    thoughts = state_for(table, 0)["vis_kort"]["bots"].map { |bot| bot["thought"] }
    assert_equal %w[pass pass pass], thoughts.map { |thought| thought["decision"] }
    assert_equal %w[mellem_pass mellem_pass mellem_pass], thoughts.map { |thought| thought["reason"] }
    assert_equal [ 1 ], thoughts.map { |thought| thought["round_number"] }.uniq
    assert(thoughts.all? { |thought| thought["choice"].size == 3 && thought["version"].is_a?(Integer) })
  end

  test "es-makker øvebord: the forhånd bot's thought is its melding of 9 with the estimates it does not make yet" do
    table = start_practice(@admin, game: "esmakker")
    table.switch_vis_kort(user: @admin, on: true, surroundings:)

    run_bot_turns

    bots = state_for(table, 0)["vis_kort"]["bots"]
    assert_equal 13, bots.first["hand"].size
    thought = bots.first["thought"]
    assert_equal({ "decision" => "bid", "reason" => "fixed_melding", "melding" => "9",
                   "expect" => { "melding" => "9", "stik" => { "self" => nil, "makker" => nil }, "makker" => nil, "points" => nil },
                   "round_number" => 1, "version" => 0 }, thought)
  end

  test "switched off, the admin's state says so and carries no hands" do
    table = start_practice(@admin, game: "esmakker")
    table.switch_vis_kort(user: @admin, on: true, surroundings:)

    outcome = table.switch_vis_kort(user: @admin, on: false, surroundings:)

    assert_equal({ "on" => false, "bots" => [] }, outcome.messages.sole.payload["state"]["vis_kort"])
  end

  test "an admin alone with bots has it on from the start" do
    table = start_practice(@admin, game: "hjerterfri")

    vis_kort = state_for(table, 0)["vis_kort"]
    assert vis_kort["on"]
    assert_equal [ 1, 2, 3 ], vis_kort["bots"].map { |bot| bot["seat"] }
  end

  %w[hjerterfri esmakker].each do |game|
    test "#{game}: a player who is no admin is refused and never gets the bots' cards" do
      user = users(:approved)
      table = start_practice(user, game:)

      outcome = table.switch_vis_kort(user:, on: true, surroundings:)

      assert_equal :vis_kort_not_allowed, outcome.refusal
      assert_nil state_for(table, 0)["vis_kort"]
    end

    test "#{game}: at a bord with another human the admin is refused, and a switch left on shows nothing" do
      table = start_with_humans(game, [ @admin, users(:erik) ])

      assert_equal :vis_kort_not_allowed, table.switch_vis_kort(user: @admin, on: true, surroundings:).refusal
      assert_nil state_for(table, 0)["vis_kort"]

      table.seats.find_by(position: 0).update!(vis_kort: true)
      assert_nil state_for(table, 0)["vis_kort"]
      assert_nil state_for(table, 1)["vis_kort"]
    end
  end

  test "it carries on to the next spil while the admin is alone with bots, and turns off when a human sits down" do
    table = start_with_humans("hjerterfri", [ @admin ])
    table.switch_vis_kort(user: @admin, on: true, surroundings:)

    alone = next_spil(table).start(user: @admin, surroundings:).table.reload
    assert state_for(alone, 0)["vis_kort"]["on"]

    waiting = next_spil(alone)
    waiting.remove_bot(user: @admin, seat: 3, surroundings:)
    waiting.sit(user: users(:erik), seat: 3, surroundings:)
    with_human = waiting.start(user: @admin, surroundings:).table.reload

    assert_not with_human.seats.find_by(position: 0).vis_kort
    assert_nil state_for(with_human, 0)["vis_kort"]
  end

  test "the bots' thoughts are kept only while someone watches" do
    table = start_practice(@admin, game: "esmakker")
    table.switch_vis_kort(user: @admin, on: false, surroundings:)

    run_bot_turns

    assert_equal [ nil ], table.seats.where.not(bot_name: nil).pluck(:bot_thought).uniq
  end

  %w[hjerterfri esmakker].each do |game|
    test "#{game}: watching never changes what the bots do" do
      watched = start_practice(@admin, game:)
      watched.switch_vis_kort(user: @admin, on: true, surroundings:)
      run_bot_turns
      unwatched = start_practice(users(:approved), game:)
      run_bot_turns

      row = ->(table) { table.current_game.current_round.slice(:passes, :plays, :actions) }
      assert_equal row.(unwatched), row.(watched)
      assert_not_equal [ nil ], watched.seats.where.not(bot_name: nil).pluck(:bot_thought).uniq
    end
  end

  private

  def surroundings = Table::Surroundings.new(scheduler: @scheduler, shuffler: Random.new(0), random: Random.new(0))

  def start_practice(user, game:)
    waiting = WaitingTable.set_up_practice(user:, game:, surroundings:).table
    waiting.start(user:, surroundings:).table.reload
  end

  # A bord the humans sit at in seat order (the first is vært), the other
  # seats bots.
  def start_with_humans(game, humans)
    waiting = WaitingTable.set_up(user: humans.first, game:, surroundings:).table
    humans.drop(1).each.with_index(1) { |human, seat| waiting.sit(user: human, seat:, surroundings:) }
    (humans.size...4).each { |seat| waiting.add_bot(user: humans.first, seat:, surroundings:) }
    waiting.start(user: humans.first, surroundings:).table.reload
  end

  # The spil ends (Table::Playing#spil_over): everyone waits at a new bord.
  def next_spil(table)
    waiting = WaitingTable.after_spil(table, table.seating.occupants)
    table.closed!
    surroundings.waiting_tables.add(waiting)
  end

  def state_for(table, seat)
    game = Game.find(table.current_game.id)
    game.state_for(seat, now: Time.current).as_json
  end

  def run_bot_turns
    while (turn = @scheduler.turns.shift)
      Table::BotPlayer.wake(**turn, surroundings:)
    end
  end
end
