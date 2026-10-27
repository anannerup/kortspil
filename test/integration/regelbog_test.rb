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
        assert_select "details.tip summary .tip-title", minimum: 5
      end
      assert_select ".regelbog-games a[href=?]", "##{game}"
    end
    assert_select "section#hjerterfri-bots h3", "Sådan spiller botterne"
    assert_select "section#hjerterfri-bytte h3", "Byttet"
    {
      "meldingsrunden" => "Meldingsrunden", "bytte" => "Trumf, es og bytterne", "spillet" => "Spillet",
      "sol" => "Sol og bordlægger"
    }.each do |part, heading|
      assert_select "section#esmakker-#{part} h3", heading
    end
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

  test "a visitor reads the page without the top bar, with a way to log in" do
    sign_out
    get regelbog_path

    assert_response :success
    assert_select "h1", "Regelbog"
    assert_select "section#esmakker"
    assert_select "#nav-regelbog", 0
    assert_select "header.auth-brand"
    assert_select ".regelbog-login a[href=?]", new_session_path, text: "Log ind"
    assert_select ".regelbog-login a[href=?]", new_registration_path
  end

  test "a signed-in player gets the top bar and no login link" do
    get regelbog_path

    assert_select "#nav-regelbog"
    assert_select ".regelbog-login", 0
  end

  test "the rules say no table talk, and that the esmakker is secret until the called suit is played" do
    get regelbog_path

    assert_select "#bordsnak", /man må ikke snakke undervejs eller kommunikere på andre måder end ved de kort, man spiller/
    assert_select "#esmakker-spillet li", /Ingen bordsnak/
    assert_select "#esmakker-bytte li", /Esmakkeren er hemmelig,\s*indtil den kaldte farve bliver spillet/
  end

  test "the page speaks of bytterne, not katten, and of no player as hun or hende" do
    get regelbog_path

    text = css_select("main").text
    assert_match(/bytterne/, text)
    assert_no_match(/\b[Kk]atten/, text)
    assert_no_match(/(?<![[:alpha:]])(hun|hende|hendes)(?![[:alpha:]])/i, text)
  end

  test "es-makker has no bots, so its part says nothing of them and no strategy advice" do
    get regelbog_path

    assert_select "#esmakker-bots", 0
    assert_no_match(/\bbot|Umenneskelig|på vej/i, css_select("#esmakker").text)
    assert_select "#esmakker .tip-mark", 0
  end

  test "es-makker never says a joker may be laid fordækt" do
    get regelbog_path

    text = css_select("#esmakker").text
    assert_match(/fordækt/, text)
    assert_no_match(/fordækt[^.]*joker|joker[^.]*fordækt/i, text)
  end

  test "es-makker's jokers: you must follow suit even with a joker, with Anders's spar konge example" do
    get regelbog_path

    text = css_select("#esmakker").text
    assert_no_match(/joker må spilles når som helst/i, text)
    assert_match(/har du en joker, slipper du ikke for at bekende/i, text)
    assert_match(/må du ikke smide jokeren for at redde kongen\. Du skal bekende med kongen\./, text)
  end
end
