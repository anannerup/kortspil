require "test_helper"

# Seam 2 for the table types (ticket 14): open, password and private
# tables, joining each, and what the lobby lists. Driven through
# the bord's actions and asserted on their outcomes and the stored rows.
class TableKindsTest < ActiveSupport::TestCase
  setup do
    @host = users(:approved)
    @erik = users(:erik)
  end

  # --- Open ---

  test "an open table is listed and anyone may sit without a password" do
    table = WaitingTable.set_up(user: @host, kind: "open", surroundings:).table

    assert table.open?
    assert_equal "open", listed.sole["kind"]
    assert_not table.sit(user: @erik, seat: 1, surroundings:).refused?
  end

  test "an unknown table type is refused" do
    assert_equal :unknown_kind, WaitingTable.set_up(user: @host, kind: "practice", surroundings:).refusal
    assert_equal :unknown_kind, WaitingTable.set_up(user: @host, kind: "secret", surroundings:).refusal
    assert_nil @host.current_table
  end

  # --- Password ---

  test "a password table stores only a digest and is listed with its type, not its password" do
    table = WaitingTable.set_up(user: @host, kind: "password", password: "hemmelig", surroundings:).table

    assert table.password?
    assert table.password_digest.present?
    assert_not_equal "hemmelig", table.password_digest
    assert table.admits?("hemmelig")
    assert_equal "password", listed.sole["kind"]
    assert_no_match "hemmelig", listed.to_json
    assert_no_match table.password_digest, listed.to_json
  end

  test "a password table needs a password" do
    outcome = WaitingTable.set_up(user: @host, kind: "password", password: " ", surroundings:)

    assert_equal :password_missing, outcome.refusal
    assert_nil @host.current_table
  end

  test "sitting at a password table takes the right password; a wrong one is a refusal" do
    table = WaitingTable.set_up(user: @host, kind: "password", password: "hemmelig", surroundings:).table

    assert_equal :wrong_password, table.sit(user: @erik, seat: 1, password: "forkert", surroundings:).refusal
    assert_equal :wrong_password, table.sit(user: @erik, seat: 1, surroundings:).refusal
    assert_not table.reload.seated?(@erik)

    assert_not table.sit(user: @erik, seat: 1, password: "hemmelig", surroundings:).refused?
    assert_not table.sit(user: @erik, seat: 2, surroundings:).refused?, "moving seats at the table needs no password"
    assert_equal 2, table.reload.seating.seat_of(@erik)
  end

  test "the wrong password reads Forkert adgangskode" do
    assert_equal "Forkert adgangskode.", I18n.t("tables.refusals.wrong_password", locale: :da)
  end

  test "the vært turns an open table into a password table and back" do
    table = WaitingTable.set_up(user: @host, surroundings:).table
    rules = table.rules.game

    assert_equal :password_missing, table.change_settings(user: @host, rules:, kind: "password", surroundings:).refusal
    assert_not table.change_settings(user: @host, rules:, kind: "password", password: "første", surroundings:).refused?
    assert_not table.change_settings(user: @host, rules:, kind: "password", surroundings:).refused?, "a blank password keeps the one set"
    assert table.reload.admits?("første")
    assert_not table.change_settings(user: @host, rules:, kind: "password", password: "anden", surroundings:).refused?
    assert table.reload.admits?("anden")

    table.change_settings(user: @host, rules:, kind: "open", surroundings:)

    assert table.reload.open?
    assert_nil table.password_digest
    assert_not table.sit(user: @erik, seat: 1, surroundings:).refused?
  end

  # --- Private ---

  test "a private table is not listed, but anyone with the link may take a free seat" do
    table = WaitingTable.set_up(user: @host, kind: "private", surroundings:).table

    assert table.private?
    assert_empty listed
    assert_not table.sit(user: @erik, seat: 3, surroundings:).refused?
    assert_equal 3, table.reload.seating.seat_of(@erik)
  end

  test "a private table still has its own entry for its waiting room" do
    table = WaitingTable.set_up(user: @host, kind: "private", surroundings:).table

    assert_equal [ table.id, "private" ], table.lobby_entry.values_at("id", "kind")
  end

  private

  def surroundings = Table::Surroundings.new(scheduler: FakeScheduler.new, shuffler: Random.new(0), random: Random.new(0))

  def listed = LobbyChannel.tables_message["tables"]
end
