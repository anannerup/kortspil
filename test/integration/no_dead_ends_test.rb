require "test_helper"

# Hard rule from the navigation spec: an approved user must never get stuck
# on a page with no way back. This walks every GET route in the app as an
# approved admin, follows redirects, and checks that the page it lands on has
# the top bar with a link to the lobby. New routes are covered automatically.
#
# A new route with a dynamic segment (e.g. /tables/:id) needs a fixture to
# fill it in: add an entry to SEGMENT_FIXTURES, keyed by "controller:param"
# (most specific) or just the param name, e.g.
#
#   "tables:id" => -> { tables(:practice) },
#
# The test fails with the route's name until you do.
class NoDeadEndsTest < ActionDispatch::IntegrationTest
  SEGMENT_FIXTURES = {
    "user_id" => -> { users(:approved) }
  }.freeze

  # Routes that are not pages an approved user navigates to.
  EXCLUDED_PATHS = [
    "/up",                # health check for the load balancer, plain text
    "/session/new",       # login and signup are for logged-out visitors,
    "/registration/new"   # who get no bar by design
  ].freeze
  # Rails' own routes (health, info, mailer previews, welcome) and mounted
  # apps such as Action Cable have no page controller of ours.
  EXCLUDED_CONTROLLER_PREFIXES = [ "rails/", "action_mailbox/", "active_storage/", "turbo/" ].freeze

  test "every page an approved admin can reach links back to the lobby" do
    sign_in_as users(:admin)
    assert page_routes.size > 5, "expected to find the app's GET routes"

    dead_ends = page_routes.filter_map do |route|
      path = fill_in_segments(route)
      get path
      follow_redirect! while response.redirect?
      next if css_select("nav.site-nav a[href='#{root_path}']").any?

      "#{route_label(route)}: #{path} ended at #{request.path} (status #{response.status})"
    end

    assert_empty dead_ends, "Dead ends, pages with no top bar linking to the lobby (#{root_path}):\n  " +
      dead_ends.join("\n  ")
  end

  private
    def page_routes
      @page_routes ||= Rails.application.routes.routes.select do |route|
        controller = route.defaults[:controller]
        verb = route.verb.to_s

        controller.present? &&
          (verb.empty? || verb.match?(/\bGET\b/)) &&
          EXCLUDED_CONTROLLER_PREFIXES.none? { |prefix| controller.start_with?(prefix) } &&
          EXCLUDED_PATHS.exclude?(bare_path(route))
      end
    end

    def fill_in_segments(route)
      bare_path(route).gsub(/[:*](\w+)/) do
        param = Regexp.last_match(1)
        fixture = SEGMENT_FIXTURES["#{route.defaults[:controller]}:#{param}"] || SEGMENT_FIXTURES[param]
        flunk "#{route_label(route)} has a :#{param} segment with no fixture. " \
          "Add \"#{route.defaults[:controller]}:#{param}\" to SEGMENT_FIXTURES in #{__FILE__}." unless fixture

        instance_exec(&fixture).to_param
      end
    end

    def bare_path(route)
      route.path.spec.to_s.sub("(.:format)", "")
    end

    def route_label(route)
      "#{route.verb.presence || 'ANY'} #{bare_path(route)} (#{route.defaults[:controller]}##{route.defaults[:action]})"
    end
end
