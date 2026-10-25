ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "test_helpers/session_test_helper"
require_relative "test_helpers/fake_scheduler"
require_relative "test_helpers/fake_clock"
require_relative "test_helpers/practice_spil"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    include PracticeSpil

    # Borde before their spil live in memory, process-wide (WaitingTables).
    setup { WaitingTables.default.clear }

    # Add more helper methods to be used by all tests here...
  end
end
