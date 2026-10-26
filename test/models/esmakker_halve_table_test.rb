require "test_helper"

# Seam 2 for ticket 06: a whole halve runde through the bord's actions
# (call_ace by the melder; choose_trump and discard by the ace's holder;
# play), each answered with every seat's state; and the selvmakker path
# when the called ace lies in the kitty.
#
# Seats: the vært (seat 0) deals runde 1, so erik (seat 1) is forhånd,
# then frida (2) and admin (3).
class EsmakkerHalveTableTest < ActiveSupport::TestCase
  setup do
    @host = users(:approved)
    @players = [ @host, users(:erik), users(:frida), users(:admin) ]
    @scheduler = FakeScheduler.new
    @clock = FakeClock.new
  end

  test "a whole halve runde: the melder calls the ace, its holder gives herself away, names trump and takes the kitty" do
    table = started_table
    erik = @players[1]
    win_bidding(table, erik, "8halve")
    deal = engine_round(table).deal
    suit = engine_view(table, 1)[:choices][:aces].find { |ace| holder(deal, ace) }
    partner = user_at(table, holder(deal, suit))
    others = @players - [ erik, partner ]

    assert_rejected :not_now, player_acts(table, :choose_trump, player: erik, trump: "H", surroundings:), erik
    outcome = player_acts(table, :call_ace, player: erik, suit:, surroundings:)
    @players.each do |player|
      view = view_of(outcome, player)
      assert_equal [ "choosing_trump", seat_of(table, partner) ], view.values_at("phase", "to_act")
      assert_equal [ seat_of(table, partner), false ], view["play"].values_at("esmakker", "selvmakker"), "#{player.username} sees the esmakker at once"
    end
    assert_rejected :not_your_turn, player_acts(table, :choose_trump, player: erik, trump: "trumfloes", surroundings:), erik
    assert_rejected :no_trumfloes_at_halve, player_acts(table, :choose_trump, player: partner, trump: "trumfloes", surroundings:), partner
    trump = suit
    assert_equal view_of(outcome, partner)["choices"]["trumps"], Esmakker::Card::SUITS, "a suit, the called ace's too"


    outcome = player_acts(table, :choose_trump, player: partner, trump:, surroundings:)
    mine = view_of(outcome, partner)
    assert_equal [ "discarding", 16, 3, true ], [ mine["phase"], mine["hand"].size, mine["play"]["kitty_cards"].size, mine["choices"]["discard"] ]
    assert_equal [ 13, trump ], [ view_of(outcome, erik)["hand"].size, view_of(outcome, erik)["play"]["trump"] ]

    assert_rejected :not_your_turn, player_acts(table, :discard, player: erik, cards: view_of(outcome, erik)["hand"].first(3), surroundings:), erik
    laid = mine["hand"].first(3)
    outcome = player_acts(table, :discard, player: partner, cards: laid, surroundings:)
    assert_equal laid.sort, view_of(outcome, partner)["play"]["discarded"].sort
    [ erik, *others ].each { |player| assert_empty laid & cards_in(message_for(outcome, player).payload), "#{player.username} never sees the cards laid away" }
    assert_equal [ "playing", 1 ], view_of(outcome, partner).values_at("phase", "to_act"), "the melder leads"

    outcome = play_out(table)
    @players.each do |player|
      result = view_of(outcome, player)["result"]
      assert_equal [ "played", "8halve", seat_of(table, partner), false, trump ], result.values_at("kind", "melding", "esmakker", "selvmakker", "trump")
    end
    assert_equal 1, @scheduler.deals.size, "the next runde follows"
  end

  test "halve with the called ace in the kitty: nobody gives herself away and the melder is selvmakker" do
    seed = (0..200).find { |candidate| kitty_ace(Esmakker::Deal.shuffled(shuffler: Random.new(candidate)), melder: 1) }
    table = started_table(seed:)
    erik = @players[1]
    win_bidding(table, erik, "8halve")
    suit = kitty_ace(engine_round(table).deal, melder: 1)

    outcome = player_acts(table, :call_ace, player: erik, suit:, surroundings:)
    @players.each do |player|
      view = view_of(outcome, player)
      assert_equal [ "choosing_trump", 1, nil, true ], [ *view.values_at("phase", "to_act"), *view["play"].values_at("esmakker", "selvmakker") ]
    end
    assert_rejected :no_trumfloes_at_halve, player_acts(table, :choose_trump, player: erik, trump: "trumfloes", surroundings:), erik

    outcome = player_acts(table, :choose_trump, player: erik, trump: suit, surroundings:)
    melder = view_of(outcome, erik)
    assert_includes melder["play"]["kitty_cards"], "A#{suit}"
    player_acts(table, :discard, player: erik, cards: melder["play"]["kitty_cards"], surroundings:)
    outcome = play_out(table)

    result = view_of(outcome, @players.first)["result"]
    assert_equal [ "played", nil, true, result["tricks_won"][1] ], result.values_at("kind", "esmakker", "selvmakker", "stik")
  end

  private

  def surroundings(seed: @seed || 0) = Table::Surroundings.new(clock: @clock, scheduler: @scheduler, shuffler: Random.new(seed), random: Random.new(seed))

  # The stored es-makker bord with its spil started, dealt with `seed`.
  def started_table(seed: 0)
    @seed = seed
    waiting = WaitingTable.set_up(user: @host, game: "esmakker", surroundings:).table
    @players.drop(1).each_with_index { |user, index| waiting.sit(user:, seat: index + 1, surroundings:) }
    Table.find(waiting.reload.start(user: @host, surroundings:).table.id)
  end

  # The seat holding the suit's ace, nil when it lies in the kitty.
  def holder(deal, suit) = Esmakker::Seats::ALL.find { |seat| deal.hand(seat).include?(Esmakker::Card.new(rank: "A", suit:)) }

  # An ace in the kitty, when the melder holds not all four (she could not call it otherwise).
  def kitty_ace(deal, melder:)
    aces = deal.kitty.select(&:ace?).map(&:suit)
    aces.find { |suit| holder(deal, suit) != melder }
  end

  # `player` (the forhånd) bids `melding`, the other three pass.
  def win_bidding(table, player, melding)
    seat = table.seating.seat_of(player)
    player_acts(table, :bid, player:, melding:, surroundings:)
    3.times { |offset| player_acts(table, :pas, player: user_at(table, (seat + 1 + offset) % 4), surroundings:) }
  end

  def user_at(table, seat) = User.find(table.seating.occupants.fetch(seat).user_id)
  def seat_of(table, user) = table.seating.seat_of(user)
  def engine_round(table) = Game.find(table.current_game.id).engine_round
  def engine_view(table, seat) = engine_round(table).view_for(seat)

  # Each seat to act plays its first legal card until the runde is complete.
  def play_out(table)
    outcome = nil
    loop do
      round = engine_round(table)
      return outcome if round.complete?

      outcome = player_acts(table, :play, player: user_at(table, round.to_act), card: engine_view(table, round.to_act)[:play][:legal_moves].first, surroundings:)
    end
  end

  def message_for(outcome, user) = outcome.messages.find { |message| message.user_id == user.id }
  def view_of(outcome, user) = message_for(outcome, user).payload["state"]["view"]
  def cards_in(payload) = payload.to_json.scan(/"([2-9TJQKA][CDHS]|X\d)"/).flatten.uniq

  def assert_rejected(reason, outcome, user)
    message = outcome.messages.sole
    assert_equal [ "rejected", reason.to_s, user.id ], [ message.payload["type"], message.payload["reason"], message.user_id ]
  end
end
