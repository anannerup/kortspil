require "test_helper"

# The regelbog: one page with a chapter per game, reached from the top bar,
# the lobby and the bord's Regler tab (TablePanel, "/regelbog#<game>").
class RegelbogTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:approved) }

  test "the page renders with a chapter per game and its parts" do
    get regelbog_path

    assert_response :success
    assert_select "h1", "Regelbog"
    %w[ hjerterfri esmakker ].each do |game|
      assert_select "section##{game}" do
        assert_select ".regelbog-short h3", "Kort fortalt"
        assert_select "section##{game}-point h3", "Point"
        assert_select "section##{game}-husets-regler h3", "Husets regler"
        assert_select "section##{game}-bots h3", "Sådan spiller botterne"
        assert_select "details.tip summary .tip-title", minimum: 5
      end
      assert_select ".regelbog-games a[href=?]", "##{game}"
    end
    assert_select "section#esmakker-meldingsrunden h3", "Meldingsrunden"
    assert_select "section#hjerterfri-bytte h3", "Byttet"
  end

  test "the house rules shown are the games' standard rules" do
    get regelbog_path

    assert_select "#hjerterfri-husets-regler", /slutter ved 100 point/
    assert_select "#esmakker-husets-regler" do
      assert_select "li", /#{TableRules::STANDARD_RUNDER} runder/
      assert_select "li", /Vip > Halve > Gode/
      assert_select "li", /8 sekunder/
    end
    assert_select "#hjerterfri-husets-regler", /Ved et bord med bots spiller man altid husets regler/
  end

  test "es-makker's lookup table has every melding on the ladder, from the standard points" do
    get regelbog_path

    assert_select ".regelbog-lookup tbody tr", 16
    assert_select ".regelbog-lookup tbody tr:first-child", /8\s*1\s*2\s*3\s*4\s*5\s*6/
    assert_select ".regelbog-lookup tbody tr", /9p\s*3\s*5\s*7\s*9\s*11\s*–/
    assert_select ".regelbog-lookup tbody tr", /Ren bordlægger\s*6/
  end

  test "example hands carry their card codes and name the cards in words" do
    get regelbog_path

    assert_select ".regelbog-cards[data-card-hand=?]", "JS TS 4S 2S", text: "spar knægt, spar 10, spar 4, spar 2"
  end

  test "the top bar and the lobby link to the regelbog" do
    get regelbog_path
    assert_select "a#nav-regelbog.tab-active[href=?][aria-current=page]", regelbog_path

    get root_path
    assert_select "a#nav-regelbog[href=?]", regelbog_path
    assert_select "#root[data-regelbog-path=?]", regelbog_path
  end

  test "the page needs a signed-in player" do
    sign_out
    get regelbog_path

    assert_redirected_to new_session_path
  end
end
