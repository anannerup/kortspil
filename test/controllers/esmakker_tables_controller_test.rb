require "test_helper"

# Seam 3 for es-makker (ticket 01): the Es-makker box on the home page
# makes an es-makker bord, the vært's settings form (runder and
# es-makker's rules, sent as the table page sends it), no bots, the start
# with four humans, and the stored table's page telling the client which
# game it plays.
class EsmakkerTablesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @host = users(:approved)
    @players = [ @host, users(:erik), users(:frida), users(:admin) ]
  end

  test "the Es-makker box makes an es-makker bord and opens its page" do
    sign_in_as @host

    assert_no_difference %w[ Table.count Game.count ] do
      post waiting_tables_path, params: { game: "esmakker" }
    end

    table = @host.current_table
    assert_equal "esmakker", table.game
    assert_redirected_to waiting_table_path(table)
    follow_redirect!
    assert_select "div#root[data-page=waiting]" do |root|
      entry = JSON.parse(root.first["data-table"])
      assert_equal [ "esmakker", 10, false ], entry.values_at("game", "runder", "bots_allowed")
      assert_equal 8, entry.dig("rules", "bank_window")
    end
  end

  test "the lobby lists an es-makker bord as es-makker" do
    WaitingTable.set_up(user: users(:erik), game: "esmakker")
    sign_in_as @host

    get root_path

    assert_select "div#root[data-page=lobby]" do |root|
      assert_equal [ "esmakker" ], JSON.parse(root.first["data-tables"]).map { |entry| entry["game"] }
    end
  end

  test "the vært saves es-makker's settings from the table page and gets the bord back" do
    table = WaitingTable.set_up(user: @host, game: "esmakker").table
    sign_in_as @host

    patch waiting_table_settings_path(table), as: :json, params: {
      kind: "open", runder: "15",
      rules: { pahaeng_order: %w[vip gode halve], joker_trumpable: "1", esmakker_banks_first: "1", bank_window: "9",
               points: { stakes: { "8" => "1", "9" => "1,5", "10" => "2", "11" => "2,5", "12" => "3", "13" => "3,5" },
                         pahaeng: "2", trumflos: "2", vip_first: "2", vip_second: "4", vip_third: "8", bank: "2",
                         sol: "3", ren_sol: "4", bordlaegger: "5", ren_bordlaegger: "7" } }
    }

    assert_response :success
    entry = response.parsed_body["table"]
    assert_equal 15, entry["runder"]
    assert_equal [ %w[vip gode halve], true, 9, 7 ], [ entry.dig("rules", "pahaeng_order"), entry.dig("rules", "joker_trumpable"), entry.dig("rules", "bank_window"), entry.dig("rules", "points", "ren_bordlaegger") ]
    assert_equal 1.5, entry.dig("rules", "points", "stakes", "9")
  end

  test "settings the rules cannot hold, and bots, are refused with a reason" do
    table = WaitingTable.set_up(user: @host, game: "esmakker").table
    sign_in_as @host

    patch waiting_table_settings_path(table), params: { kind: "open", runder: "0", rules: { bank_window: "8" } }, as: :json
    assert_response :unprocessable_entity
    assert_equal "Antal runder skal være et helt tal fra 1 til 50.", response.parsed_body["error"]

    patch waiting_table_settings_path(table), params: { kind: "open", runder: "10", rules: { bank_window: "3" } }, as: :json
    assert_response :unprocessable_entity
    assert_equal "Reglerne kunne ikke gemmes. Tjek tallene.", response.parsed_body["error"]

    post waiting_table_bot_path(table), params: { position: 2 }, as: :json
    assert_response :unprocessable_entity
    assert_equal "Es-makker spilles af fire mennesker; der er ingen bots endnu.", response.parsed_body["error"]
  end

  test "a non-vært cannot change the settings" do
    table = WaitingTable.set_up(user: @host, game: "esmakker").table
    table.sit(user: users(:erik), seat: 1)
    sign_in_as users(:erik)

    patch waiting_table_settings_path(table), params: { kind: "open", runder: "12", rules: { bank_window: "8" } }, as: :json

    assert_response :unprocessable_entity
    assert_equal 10, table.reload.rules.runder
  end

  test "four humans start the spil, and the stored table's page says it is es-makker" do
    table = WaitingTable.set_up(user: @host, game: "esmakker").table
    @players.drop(1).each_with_index { |user, index| table.sit(user:, seat: index + 1) }
    sign_in_as @host

    assert_difference -> { Table.count } => 1, -> { Game.count } => 1 do
      post waiting_table_start_path(table), as: :json
    end
    stored = Table.last
    assert_equal "esmakker", stored.game

    get table_path(stored)
    assert_select "div#root[data-page=table][data-game=esmakker]"
  end
end
