require "test_helper"

# Request tests for ticket 19: the lobby banner for a frakoblet player,
# "Forlad bordet" in a spil in progress, and no way back after forladt.
class LeavingControllerTest < ActionDispatch::IntegrationTest
  setup do
    @players = [ users(:approved), users(:admin), users(:erik), users(:frida) ]
    @scheduler = FakeScheduler.new
  end

  test "a frakoblet player sees the banner with the time left and a way back; the Ved bordet marker stays" do
    travel_to Time.utc(2026, 10, 25, 12) do
      table = started_table
      commands.disconnect(table:, user: users(:erik))
      travel 18.seconds
      sign_in_as users(:erik)

      get root_path

      assert_select ".return-banner[role=alert]", text: /Dit spil er i gang — de venter på dig \(0:42\)/ do
        assert_select "[data-countdown='42']"
        assert_select "a[href='#{table_path(table)}']", text: "Tilbage til bordet"
      end
      assert_select "#nav-spil .marker", text: "Ved bordet"
    end
  end

  test "no banner for a player at a practice table or without a spil in progress" do
    commands.start_practice(user: users(:erik))
    sign_in_as users(:erik)

    get root_path

    assert_select ".return-banner", count: 0
  end

  test "Forlad bordet in a spil in progress: back to the lobby, a bot plays on, and the table cannot be opened again" do
    table = started_table
    sign_in_as users(:erik)

    post table_departure_path(table)

    assert_redirected_to root_path
    assert table.reload.playing?
    assert table.seating.occupants[2].bot?
    get table_path(table)
    assert_redirected_to root_path
    follow_redirect!
    assert_select ".flash-alert", text: /Du har forladt spillet/
    assert_select ".return-banner", count: 0
  end

  private

  def commands = TableCommands.new(scheduler: @scheduler)

  def started_table
    table = commands.create_table(user: @players.first).table
    @players.drop(1).each.with_index(1) { |player, seat| commands.sit(table:, user: player, seat:) }
    commands.start(table:, user: @players.first)
    table.reload
  end
end
