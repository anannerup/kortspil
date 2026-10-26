require "test_helper"

# Seam 2 for ticket 04: the called ace, the jokers with the bord's trump
# setting and fordækt through the bord's actions (lay_fordaekt, play),
# every seat told what it may see. The runde's deal is set on the stored
# row before anyone acts, so the hands are known.
#
# Seats: the vært (seat 0) deals runde 1, so erik (seat 1) is forhånd and,
# here, the melder; then frida (2) and admin (3).
class EsmakkerAceFordaektTableTest < ActiveSupport::TestCase
  # Erik has no diamonds after the kitty; frida holds the diamond ace,
  # admin one diamond, the vært the rest of them.
  HANDS = {
    1 => %w[AS KS QS AH KH QH JH AC KC QC JC TC 9C],
    2 => %w[AD 3D 2H 3H 4H 5H 6H 7H 8H 9H TH 5C 6C],
    3 => %w[4D 2S 3S 4S 5S 6S 7S 8S 9S TS 7C 8C X2]
  }.freeze
  KITTY = %w[2C 3C X3].freeze

  setup do
    @host = users(:approved)
    @players = [ @host, users(:erik), users(:frida), users(:admin) ]
    @scheduler = FakeScheduler.new
    @clock = FakeClock.new
  end

  test "fordækt through the bord: laid face down, led as the ace's suit, its face never shown to the others" do
    table = declared_table
    host, erik, frida, admin = @players

    assert_rejected :not_your_turn, player_acts(table, :lay_fordaekt, player: frida, card: "AD", surroundings:), frida
    outcome = player_acts(table, :lay_fordaekt, player: erik, card: "9C", surroundings:)
    assert_equal 4, outcome.messages.size
    assert_equal({ "seat" => 1, "card" => "9C", "waiting" => true }, view_of(outcome, erik)["play"]["fordaekt"])
    [ host, frida, admin ].each do |player|
      assert_equal({ "seat" => 1, "card" => nil, "waiting" => true }, view_of(outcome, player)["play"]["fordaekt"])
      assert_not_includes cards_in(message_for(outcome, player).payload), "9C", "#{player.username} sees only its back"
    end

    outcome = player_acts(table, :play, player: erik, card: "9C", surroundings:)
    assert_equal [ { "seat" => 1, "card" => "fordaekt", "fordaekt" => true } ], view_of(outcome, frida)["play"]["current_trick"]
    assert_equal %w[3D AD], view_of(outcome, frida)["play"]["legal_moves"].sort, "she follows diamonds; the ace is not forced"

    player_acts(table, :play, player: frida, card: "AD", surroundings:)
    player_acts(table, :play, player: admin, card: "4D", surroundings:)
    outcome = player_acts(table, :play, player: host, card: "2D", surroundings:)
    assert_equal "9C", view_of(outcome, erik)["play"]["last_trick"].first["card"]
    [ host, frida, admin ].each do |player|
      play = view_of(outcome, player)["play"]
      assert_equal({ "seat" => 1, "card" => "fordaekt", "fordaekt" => true }, play["last_trick"].first, "never turned for #{player.username}")
      assert_equal [ 2, nil, 2 ], [ play["last_trick_winner"], play["fordaekt"]["card"], play["esmakker"] ]
      assert_not_includes cards_in(message_for(outcome, player).payload), "9C"
    end
  end

  test "a seat void in the ace's suit may trump the ace once it lies in the stik, and takes the stik" do
    table = declared_table(hands: { 1 => %w[2D AS KS QS AH KH QH JH AC KC QC JC TC], 2 => HANDS[2], 3 => %w[2S 3S 4S 5S 6S 3C 4C 7C 8C 9C TS 7S X2] },
                           kitty: %w[9S JS 8S], discard: %w[9S JS 8S])
    host, erik, frida, admin = @players

    player_acts(table, :play, player: erik, card: "2D", surroundings:)
    outcome = player_acts(table, :play, player: frida, card: "AD", surroundings:)
    assert_includes view_of(outcome, admin)["play"]["legal_moves"], "2S"
    player_acts(table, :play, player: admin, card: "2S", surroundings:)
    outcome = player_acts(table, :play, player: host, card: "4D", surroundings:)
    assert_equal 3, view_of(outcome, host)["play"]["last_trick_winner"]
  end

  test "a led joker leaves no suit to follow at the bord" do
    table = declared_table
    _host, erik, frida, _admin = @players
    outcome = player_acts(table, :play, player: erik, card: "X3", surroundings:)
    assert_equal HANDS[2].sort, view_of(outcome, frida)["play"]["legal_moves"].sort
  end

  test "a led joker resists trump at a standard bord" do
    assert_equal 1, joker_stik_winner(joker_trumpable: "0")
  end

  test "a led joker is beaten by trump where the vært set it so" do
    assert_equal 3, joker_stik_winner(joker_trumpable: "1")
  end

  private

  def surroundings(seed: 0) = Table::Surroundings.new(clock: @clock, scheduler: @scheduler, shuffler: Random.new(seed), random: Random.new(seed))

  # The stored es-makker bord with its spil started; erik bid 8, named
  # spades, called the diamond ace, laid three away and took the kitty
  # up, so that he holds `hands[1]` + `kitty` − `discard`. The deal behind
  # it: the kitty holds three of those cards, and erik is dealt the rest
  # of them and the three he lays away. `joker_trumpable` is the vært's
  # setting ("0" / "1").
  def declared_table(hands: HANDS, kitty: KITTY, discard: %w[2C 3C TC], joker_trumpable: "0")
    after = hands[1] + kitty - discard
    taken = ((kitty & after) + (after - kitty).reverse).first(3)
    hands = hands.merge(1 => (after - taken) + discard)
    kitty = taken
    waiting = WaitingTable.set_up(user: @host, game: "esmakker", surroundings:).table
    form = { pahaeng_order: "vip,halve,gode", joker_trumpable:, esmakker_banks_first: "1", bank_window: "8" }
    assert_not waiting.change_settings(user: @host, rules: form, kind: "open", runder: "10", surroundings:).refused?
    @players.drop(1).each_with_index { |user, index| waiting.sit(user:, seat: index + 1, surroundings:) }
    table = waiting.reload.start(user: @host, surroundings:).table
    table.current_game.current_round.update_column(:deal, deal_with(hands:, kitty:).to_s)
    table = Table.find(table.id)

    _host, erik, frida, admin = @players
    player_acts(table, :bid, player: erik, melding: "8", surroundings:)
    [ frida, admin, @host ].each { |player| player_acts(table, :pas, player:, surroundings:) }
    player_acts(table, :choose_trump, player: erik, trump: "S", surroundings:)
    player_acts(table, :call_ace, player: erik, suit: "D", surroundings:)
    player_acts(table, :discard, player: erik, cards: discard, surroundings:)
    table
  end

  # Erik leads a joker, frida sets hearts, admin trumps, the vært discards.
  def joker_stik_winner(joker_trumpable:)
    table = declared_table(joker_trumpable:)
    host, erik, frida, admin = @players
    player_acts(table, :play, player: erik, card: "X3", surroundings:)
    player_acts(table, :play, player: frida, card: "2H", surroundings:)
    player_acts(table, :play, player: admin, card: "2S", surroundings:)
    view_of(player_acts(table, :play, player: host, card: "5D", surroundings:), host)["play"]["last_trick_winner"]
  end

  def deal_with(hands:, kitty:)
    parse = ->(codes) { codes.map { |code| Esmakker::Card.parse(code) } }
    rest = Esmakker::Card.deck - parse.(hands.values.flatten + kitty)
    filled = (0..3).map { |seat| parse.(hands.fetch(seat, [])).then { |own| own + rest.shift(Esmakker::Deal::HAND_SIZE - own.size) } }
    Esmakker::Deal.new(hands: filled, kitty: parse.(kitty))
  end

  def message_for(outcome, user) = outcome.messages.find { |message| message.user_id == user.id }
  def view_of(outcome, user) = message_for(outcome, user).payload["state"]["view"]
  def cards_in(payload) = payload.to_json.scan(/"([2-9TJQKA][CDHS]|X\d)"/).flatten.uniq

  def assert_rejected(reason, outcome, user)
    message = outcome.messages.sole
    assert_equal [ "rejected", reason.to_s, user.id ], [ message.payload["type"], message.payload["reason"], message.user_id ]
  end
end
