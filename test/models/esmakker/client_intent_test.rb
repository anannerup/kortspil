require "test_helper"

module Esmakker
  # A client's action (TableChannel, ClientIntents in the client) as the
  # runde's intent, beside the log's tokens (Round.token, Round.intent).
  class ClientIntentTest < ActiveSupport::TestCase
    test "every es-makker action the client sends becomes its intent" do
      cards = %w[2C X1 AH]
      expected = {
        [ "bid", { "melding" => "10halve" } ] => Bidding::Bid.new(melding: Melding.parse("10halve")),
        [ "pas", {} ] => Bidding::Pas.new,
        [ "det_kan_jeg_selv", {} ] => Bidding::DetKanJegSelv.new,
        [ "gaa_med", {} ] => Bidding::GaaMed.new,
        [ "claim_jernhaand", {} ] => Bidding::ClaimJernhaand.new,
        [ "choose_trump", { "trump" => "trumfloes" } ] => ChooseTrump.new(trump: Trump.parse("trumfloes")),
        [ "call_ace", { "suit" => "D" } ] => CallAce.new(suit: "D"),
        [ "turn_card", {} ] => TurnCard.new,
        [ "accept_trump", {} ] => AcceptTrump.new,
        [ "bank", {} ] => Bank.new,
        [ "discard", { "cards" => cards } ] => Discard.new(cards: cards.map { |code| Card.parse(code) }),
        [ "lay_fordaekt", { "card" => "3S" } ] => LayFordaekt.new(card: Card.parse("3S")),
        [ "play", { "card" => "X2" } ] => PlayCard.new(card: Card.parse("X2"))
      }

      expected.each { |(action, data), intent| assert_equal intent, Round.client_intent(action, data), action }
    end

    test "a code that is no melding, trump or card becomes an intent holding nothing, which the runde rejects" do
      assert_equal Bidding::Bid.new(melding: nil), Round.client_intent("bid", { "melding" => "14" })
      assert_equal ChooseTrump.new(trump: nil), Round.client_intent("choose_trump", { "trump" => "spar" })
      assert_equal LayFordaekt.new(card: nil), Round.client_intent("lay_fordaekt", { "card" => "zz" })
      assert_equal Discard.new(cards: [ nil ]), Round.client_intent("discard", { "cards" => "zz" })
      assert_equal CallAce.new(suit: ""), Round.client_intent("call_ace", {})
    end

    test "an action es-makker does not know is no intent" do
      assert_nil Round.client_intent("choose_moon", { "option" => "add_to_others" })
      assert_nil Round.client_intent("pass", { "cards" => %w[2C 3C 4C] })
      assert_nil Round.client_intent("bankslut", {})
    end
  end
end
