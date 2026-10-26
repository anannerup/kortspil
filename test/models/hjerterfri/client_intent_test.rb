require "test_helper"

module Hjerterfri
  # A client's action (TableChannel, ClientIntents in the client) as the
  # runde's intent.
  class ClientIntentTest < ActiveSupport::TestCase
    test "the pass, the play and the moon choice become their intents, by card codes" do
      assert_equal Pass.new(cards: %w[QS AH KH]), Round.client_intent("pass", { "cards" => %w[QS AH KH] })
      assert_equal Play.new(card: "2C"), Round.client_intent("play", { "card" => "2C" })
      assert_equal MoonChoice.new(option: "subtract_from_self"), Round.client_intent(:choose_moon, { "option" => "subtract_from_self" })
    end

    test "an action hjerterfri does not know is no intent" do
      assert_nil Round.client_intent("bid", { "melding" => "9" })
      assert_nil Round.client_intent("bank", {})
    end
  end
end
