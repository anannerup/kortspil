require "test_helper"

class NavigationTest < ActionDispatch::IntegrationTest
  PAGES = {
    "lobby" => [ :spil, -> { root_path } ],
    "friends" => [ :konto, -> { friendships_path } ],
    "change password" => [ :konto, -> { edit_password_path } ],
    "admin dashboard" => [ :konto, -> { admin_root_path } ],
    "all users" => [ :konto, -> { admin_users_path } ],
    "admin set password" => [ :konto, -> { edit_admin_user_password_path(users(:approved)) } ]
  }.freeze

  PAGES.each do |name, (area, path)|
    test "the #{name} page has the bar with Spil, Konto, username and Log ud, and #{area} active" do
      sign_in_as users(:admin)
      get instance_exec(&path)

      assert_response :success
      assert_select "nav.site-nav" do
        assert_select "a.brand[href=?]", root_path, text: "Kortspil"
        assert_select "a#nav-spil", /Spil/
        assert_select "a#nav-konto[href=?]", friendships_path, /Konto/
        assert_select ".username", "Anders"
        assert_select "form[action=?] button", session_path, text: "Log ud"
        assert_select "a.tab-active[aria-current=page]", count: 1
        assert_select "a#nav-#{area}.tab-active"
      end
    end
  end

  test "Spil points to the lobby when the user isn't at a bord" do
    sign_in_as users(:approved)
    get friendships_path

    assert_select "a#nav-spil[href=?]", root_path
    assert_select "a#nav-spil .marker", count: 0
  end

  test "the Konto sub-navigation is on Konto pages with the current page marked" do
    sign_in_as users(:admin)

    { friendships_path => "Venner", edit_password_path => "Skift adgangskode",
      admin_root_path => "Admin", admin_users_path => "Admin" }.each do |path, current|
      get path
      assert_select "nav.konto-nav a[aria-current=page]", { count: 1, text: /#{current}/ }, path
    end
  end

  test "the lobby has no Konto sub-navigation" do
    sign_in_as users(:admin)
    get root_path

    assert_select "nav.konto-nav", count: 0
  end

  test "admin pages keep their own sub-navigation under the Konto one" do
    sign_in_as users(:admin)
    get admin_users_path

    assert_select "nav.konto-nav"
    assert_select "nav.admin-nav a[aria-current=page]", "Alle brugere"
  end

  test "Admin is only in the sub-navigation for admins" do
    sign_in_as users(:approved)
    get friendships_path
    assert_select "nav.konto-nav a", text: "Admin", count: 0
    assert_select "a[href=?]", admin_root_path, count: 0

    sign_in_as users(:admin)
    get friendships_path
    assert_select "nav.konto-nav a[href=?]", admin_root_path, text: "Admin"
  end

  test "the friend-request badge is on Konto and Venner, also from the lobby" do
    sign_in_as users(:approved)
    get root_path

    assert_select "a#nav-konto .badge", "1"

    get friendships_path
    assert_select "a#nav-konto .badge", "1"
    assert_select "nav.konto-nav a[href=?] .badge", friendships_path, "1"
  end

  test "no badge without pending requests" do
    sign_in_as users(:admin)
    get friendships_path

    assert_select ".site-nav .badge", count: 0
    assert_select ".konto-nav .badge", count: 0
  end

  test "pending and rejected users see no bar, only the waiting page with Log ud" do
    [ users(:pending), users(:rejected) ].each do |user|
      sign_in_as user
      get approval_path

      assert_response :success
      assert_select "nav.site-nav", count: 0
      assert_select "nav.konto-nav", count: 0
      assert_select "form[action=?] button", session_path, text: "Log ud"
    end
  end

  test "logged-out visitors see no bar on login and signup" do
    [ new_session_path, new_registration_path ].each do |path|
      get path
      assert_response :success
      assert_select "nav.site-nav", count: 0
    end
  end

  test "sub-pages link back to their parent" do
    sign_in_as users(:admin)

    get edit_admin_user_password_path(users(:approved))
    assert_select ".back-link a[href=?]", admin_users_path, /Alle brugere/

    get edit_password_path
    assert_select ".back-link a[href=?]", root_path
  end

  test "a missing page is a 404 with the bar for approved users" do
    sign_in_as users(:approved)
    get "/findes-ikke"

    assert_response :not_found
    assert_select "nav.site-nav a[href=?]", root_path
    assert_select "h1", "Siden findes ikke"
  end

  test "a missing record is a 404 with the bar" do
    sign_in_as users(:admin)
    get edit_admin_user_password_path(user_id: 0)

    assert_response :not_found
    assert_select "nav.site-nav"
  end

  test "a non-admin on an admin page gets the 404 page with the bar, not a blank page" do
    sign_in_as users(:approved)
    get admin_root_path

    assert_response :not_found
    assert_select "nav.site-nav a[href=?]", root_path
  end

  test "a missing page links to the front page for visitors and pending users, without the bar" do
    get "/findes-ikke"
    assert_response :not_found
    assert_select "nav.site-nav", count: 0
    assert_select "a[href=?]", root_path, text: "Til forsiden"

    sign_in_as users(:pending)
    get "/findes-ikke"
    assert_select "nav.site-nav", count: 0
    assert_select "a[href=?]", root_path, text: "Til forsiden"
  end

  test "the 500 page has the bar for approved users and Til forsiden otherwise" do
    get "/500"
    assert_response :internal_server_error
    assert_select "nav.site-nav", count: 0
    assert_select "a[href=?]", root_path, text: "Til forsiden"

    sign_in_as users(:approved)
    get "/500"
    assert_select "nav.site-nav a[href=?]", root_path
  end
end
