ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "test_helpers/session_test_helper"
require_relative "test_helpers/fake_scheduler"
require_relative "test_helpers/fake_clock"
require_relative "test_helpers/practice_spil"
require_relative "test_helpers/player_acts"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Vite builds the test assets on demand (autoBuild in config/vite.json)
    # in whichever process first renders a page. With parallel workers each
    # one would start its own build into the same public/vite-test after a
    # frontend change, and one worker reads the manifest while another
    # empties the folder. Build once here, before the workers fork; they
    # then find the build up to date (a failed build still shows up as
    # errors in the tests that render a page).
    parallelize_before_fork { ViteRuby.commands.build if ViteRuby.config.auto_build }

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    include PracticeSpil
    include PlayerActs

    # Borde before their spil live in memory, process-wide (WaitingTables),
    # and so does the table chat (TableChat). Stored table ids are reused
    # once a test's transaction rolls back, so a chat log left behind would
    # turn up at the next test's table.
    setup do
      WaitingTables.default.clear
      TableChat.default.clear
    end

    # Add more helper methods to be used by all tests here...
  end
end
