require "test_helper"

# A bot melder who is not forhånd may lay fordækt out of turn, before the
# forhånd leads, as a human melder may (Esmakker::Play): the bord wakes
# bots only on their turn, so it asks the melder's bot at once when the
# play starts (Table::Playing#out_of_turn). The forhånd stays the seat to
# act, and a bot that does not lay fordækt leaves no trace.
#
# Seats: the vært (0) deals, so erik (1) is forhånd; frida (2) is the
# melder, and a bot takes her seat over before she lays away; admin (3).
class EsmakkerFordaektOutOfTurnTableTest < ActiveSupport::TestCase
  # Frida melder 8 in spades and calls the diamond ace; she has no
  # diamonds, nor has the kitty, so she is void in diamonds after the kitty
  # whatever her bot lays away.
  HANDS = {
    1 => %w[AD 3D 2H 3H 4H 5H 6H 7H 8H 9H TH 5C 6C],
    2 => %w[AS KS QS AH KH QH JH AC KC QC 2C 3C TC],
    3 => %w[4D 2S 3S 4S 5S 6S 7S 8S 9S TS 7C 8C X2]
  }.freeze
  KITTY = %w[JC 9C X3].freeze

  setup do
    @host = users(:approved)
    @players = [ @host, users(:erik), users(:frida), users(:admin) ]
    @scheduler = FakeScheduler.new
  end

  test "Svær as melder lays fordækt before the forhånd leads, and the forhånd is still to lead" do
    table, outcome = bot_melder_lays_away(level: "svaer")
    erik = @players[1]

    view = view_of(outcome, erik)
    assert_equal 1, view["to_act"], "the forhånd leads; fordækt is no turn"
    assert_equal({ "seat" => 2, "card" => nil, "waiting" => true }, view["play"]["fordaekt"])
    assert_equal 12, view["card_counts"]["2"]
    game = table.current_game
    assert_equal({ seat: 2, card: "AH", waiting: true }, game.engine_round.view_for(2)[:play][:fordaekt], "§6.4: the lowest card of its weakest side suit (it laid the rest of its hearts away)")
    assert_empty game.bots_out_of_turn, "asked once: it may not lay another"
  end

  test "the first bot as melder lays fordækt out of turn at random: sometimes it does, sometimes not, and then nothing shows" do
    laid = (0..5).map do |seed|
      table, outcome = bot_melder_lays_away(level: "mellem", seed:)
      game = table.current_game
      view = view_of(outcome, @players[1])
      assert_equal 1, view["to_act"]
      if view["play"]["fordaekt"]
        assert_equal({ "seat" => 2, "card" => nil, "waiting" => true }, view["play"]["fordaekt"])
      else
        assert_equal game.engine_round.actions.size, @version_after_discard, "no step was taken"
        assert_equal [ 2 ], game.bots_out_of_turn, "the option stays the engine's until the forhånd leads"
      end
      Table.where(id: table.id).find_each(&:closed!)
      !view["play"]["fordaekt"].nil?
    end

    assert_includes laid, true
    assert_includes laid, false
  end

  test "a human melder is not asked by the bord; she lays fordækt herself" do
    table = declared_table
    outcome = player_acts(table, :discard, player: @players[2], cards: %w[2C 3C TC], surroundings:)

    assert_nil view_of(outcome, @players[1])["play"]["fordaekt"]
    assert_empty table.current_game.bots_out_of_turn
    assert_empty @scheduler.turns
  end

  private

  def surroundings(seed: 0) = Table::Surroundings.new(scheduler: @scheduler, shuffler: Random.new(seed), random: Random.new(seed))

  # Frida declares, then a bot at `level` takes her seat over and lays
  # away on its turn: the play starts, and the bord asks it about fordækt.
  # Returns the table and the outcome of the bot's turn.
  def bot_melder_lays_away(level:, seed: 0)
    table = declared_table(seed:)
    game = table.current_game
    table.seating.take_over!(2, game:, at_play: game.version)
    Seat.find_by!(table:, position: 2).update!(bot_level: level)
    game = Game.find(game.id)
    outcome = Table::BotPlayer.wake(game_id: game.id, seat: 2, version: game.version, surroundings: surroundings(seed:))
    @version_after_discard = Game.find(game.id).engine_round.actions.size
    [ Table.find(table.id), outcome ]
  end

  # The stored es-makker bord with the four humans, the deal set, and
  # frida's 8 in spades with the diamond ace called.
  def declared_table(seed: 0)
    waiting = WaitingTable.set_up(user: @host, game: "esmakker", surroundings: surroundings(seed:)).table
    @players.drop(1).each_with_index { |user, index| waiting.sit(user:, seat: index + 1, surroundings:) }
    table = waiting.reload.start(user: @host, surroundings:).table
    table.current_game.current_round.update_column(:deal, deal_with(hands: HANDS, kitty: KITTY).to_s)
    table = Table.find(table.id)

    host, erik, frida, admin = @players
    player_acts(table, :pas, player: erik, surroundings:)
    player_acts(table, :bid, player: frida, melding: "8", surroundings:)
    [ admin, host ].each { |player| player_acts(table, :pas, player:, surroundings:) }
    player_acts(table, :choose_trump, player: frida, trump: "S", surroundings:)
    player_acts(table, :call_ace, player: frida, suit: "D", surroundings:)
    table
  end

  def deal_with(hands:, kitty:)
    parse = ->(codes) { codes.map { |code| Esmakker::Card.parse(code) } }
    rest = Esmakker::Card.deck - parse.(hands.values.flatten + kitty)
    filled = (0..3).map { |seat| parse.(hands.fetch(seat, [])).then { |own| own + rest.shift(Esmakker::Deal::HAND_SIZE - own.size) } }
    Esmakker::Deal.new(hands: filled, kitty: parse.(kitty))
  end

  def view_of(outcome, user) = outcome.messages.find { |message| message.user_id == user.id }.payload["state"]["view"]
end
