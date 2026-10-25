require "test_helper"

module Hjerterfri
  class BotTest < ActiveSupport::TestCase
    def bot(level) = Bot.new(level:, random: Random.new(0))

    # ── Let (spec §4) ───────────────────────────────────────────────────

    test "Let ducks with the highest card that still loses the stik" do
      assert_equal "8D", bot(:let).choose_play(view(legal: %w[3D 8D JD AD], trick: %w[TD 2D]))
    end

    test "Let, unable to duck, plays its lowest early and its highest last" do
      assert_equal "JD", bot(:let).choose_play(view(legal: %w[JD QD AD], trick: %w[TD]))
      assert_equal "AD", bot(:let).choose_play(view(legal: %w[JD QD AD], trick: %w[TD 2D 3D]))
    end

    test "Let dumps Q♠ under a higher spade, and never wins with it while another spade will do" do
      assert_equal "QS", bot(:let).choose_play(view(legal: %w[3S QS], trick: %w[KS]))
      assert_equal "AS", bot(:let).choose_play(view(legal: %w[QS AS], trick: %w[TS 2S 3S]))
    end

    test "Let discards Q♠, then the highest heart, then the highest card" do
      assert_equal "QS", bot(:let).choose_play(view(legal: %w[2C QS AH KD], trick: %w[5D]))
      assert_equal "JH", bot(:let).choose_play(view(legal: %w[AC 4H JH KS], trick: %w[5D]))
      assert_equal "KD", bot(:let).choose_play(view(legal: %w[4C TC 9S KD], trick: %w[5H]))
    end

    test "Let leads its lowest card, never hearts, Q♠ or A♠/K♠ while another card will do" do
      assert_equal "5D", bot(:let).choose_play(view(legal: %w[7C 5D 2H 9S], trick: []))
      assert_equal "9D", bot(:let).choose_play(view(legal: %w[QS KS AS 9D], trick: []))
      assert_equal "3H", bot(:let).choose_play(view(legal: %w[3H 9H], trick: []))
    end

    test "Let passes Q♠ with fewer than three spades under it, then the highest hearts" do
      assert_equal %w[QS JH 9H], bot(:let).choose_pass(%w[2C 3C 4C 5D 6D QS 2S 3H 9H JH 7D 8D 9D])
      assert_equal %w[JH 9H 6H], bot(:let).choose_pass(%w[2C 3C 4C 5D 6D QS 2S 3S 4S 9H JH 7D 6H])
    end

    test "Let passes A♠ and K♠ without Q♠, and keeps them with it" do
      assert_equal %w[AS KS JH], bot(:let).choose_pass(%w[2C 3C 4C 5D 6D KS AS 3S 3H 9H JH 7D 8D])
      assert_equal %w[QS 9H 3H], bot(:let).choose_pass(%w[2C 3C 4C 5D 6D KS AS QS 3H 9H 2H 7D 8D])
    end

    # ── Mellem (spec §5) ────────────────────────────────────────────────

    test "Mellem passes a short diamond suit away to make a void, and keeps low hearts and spades" do
      pass = bot(:mellem).choose_pass(%w[2C 3C 4C 5C 6C 4D 9D 2S 3S 4S 3H 5H 8H])

      assert_includes pass, "9D"
      assert_includes pass, "4D"
      assert_empty pass & %w[2S 3S 4S 3H 5H]
    end

    test "Mellem passes Q♠ with fewer than three other spades, and A♥ K♥ Q♥" do
      assert_equal %w[QS AH KH], bot(:mellem).choose_pass(%w[QS 2S AH KH 5H 2C 3C 4C 5C 6C 7C 8C 9C])
    end

    test "Mellem takes a clean stik when it plays last, shedding its highest card" do
      assert_equal "KD", bot(:mellem).choose_play(view(legal: %w[4D 9D KD], trick: %w[5D 2D 3D]))
    end

    test "Mellem discards A♠/K♠ while Q♠ is out, before hearts" do
      assert_equal "KS", bot(:mellem).choose_play(view(legal: %w[AC 4H JH KS], trick: %w[5D]))
    end

    test "Mellem hunts Q♠ by leading a low spade when it holds none of Q♠, K♠, A♠" do
      assert_equal "3S", bot(:mellem).choose_play(view(legal: %w[3S 8S 5D 7C], trick: [], tricks: four_tricks))
    end

    test "Mellem blocks a moon by taking a stik with points with its lowest winning card" do
      # Seat 2 alone has taken 25 penalty points.
      tricks = [ trick(%w[AH 2H 3H 4H], leader: 2, winner: 2), trick(%w[KH 5H 6H 7H], leader: 2, winner: 2),
                 trick(%w[QH 8H 9H TH], leader: 2, winner: 2), trick(%w[KS QS 4S 5S], leader: 2, winner: 2) ]
      view = view(legal: %w[4C 9C KC], trick: %w[8C JH], tricks:)

      assert_equal "9C", bot(:mellem).choose_play(view)
    end

    test "Q♠ alone is no moon threat: Mellem ducks a stik with a heart in it" do
      # Seat 2 alone has taken 13 penalty points, all of them Q♠.
      view = view(legal: %w[4C 9C KC], trick: %w[8C 2H], tricks: [ trick(%w[KS QS 4S 5S], leader: 2, winner: 2) ])

      assert_equal "4C", bot(:mellem).choose_play(view)
    end

    test "Mellem takes J♦ with its lowest winning diamond when −10 is on" do
      view = view(legal: %w[3D QD AD], trick: %w[JD 5D], rules: Rules.new(jack_of_diamonds_minus_ten: true))

      assert_equal "QD", bot(:mellem).choose_play(view)
    end

    test "with J♦ −10 on, Mellem never throws J♦ to another seat, nor leads it while it can be lost" do
      rules = Rules.new(jack_of_diamonds_minus_ten: true)
      discard = view(legal: %w[JD 4D 3D 9S 8S 7S], trick: %w[5C], rules:)
      lead = view(legal: %w[JD 9S], trick: [], hand: %w[JD 9S], tricks: four_tricks, rules:)

      assert_equal "9S", bot(:mellem).choose_play(discard)
      assert_equal "9S", bot(:mellem).choose_play(lead)
    end

    # ── Svær (spec §6) ──────────────────────────────────────────────────

    test "Svær leads a card that loses for sure before a lower card that may win" do
      # Hearts are broken; every heart still out beats 2♥, while 7♠ (or 9♣) can win.
      tricks = four_tricks[0..2] + [ trick(%w[JC 3C 4H TC], leader: 1, winner: 1) ]
      view = view(legal: %w[9C 2H 7S KS], trick: [], tricks:)

      assert_equal "7S", bot(:mellem).choose_play(view)
      assert_equal "2H", bot(:svaer).choose_play(view)
    end

    test "Svær takes a clean stik early with its highest card when nobody after it is likely to drop points" do
      view = view(legal: %w[4D 9D AD], trick: %w[7D 8D], hand: %w[4D 9D AD 2C 3S 4S 5S 6S 7S 8S 9S])

      assert_equal "4D", bot(:mellem).choose_play(view)
      assert_equal "AD", bot(:svaer).choose_play(view)
    end

    test "Svær throws off the card likeliest to win a stik later before a low heart" do
      view = view(legal: %w[AD 2H 3H 9S], trick: %w[5C], hand: %w[AD 2H 3H 9S 8S 7S], tricks: four_tricks)

      assert_equal "3H", bot(:mellem).choose_play(view)
      assert_equal "AD", bot(:svaer).choose_play(view)
    end

    test "Svær passes Q♠ even with four other spades; Mellem keeps it" do
      hand = %w[QS 2S 3S 4S 5S 2C 3C 4C 5C 6C 2D 3D 4D]

      assert_includes bot(:svaer).choose_pass(hand), "QS"
      refute_includes bot(:mellem).choose_pass(hand), "QS"
    end

    # Anders, 2026-10-25: cards received in the pass tell where the giver
    # is short. The seat passing left receives from seat 3.
    test "a bot that received three diamonds won't lead a high diamond from the second stik on" do
      hand = %w[9C JD QD KD 8S 9S TS 5H 6H 7H 8H 9H]
      tricks = [ trick(%w[2C 3C 4C 5C], leader: 2, winner: 1), trick(%w[6C 7C 8C TC], leader: 1, winner: 0),
                 trick(%w[2S 3S 4S 5S], leader: 0, winner: 3) ]
      after_pass = view(legal: hand - %w[5H 6H 7H 8H 9H], trick: [], hand:, tricks:)
                   .merge(own_pass: %w[AH KH AS], received_cards: %w[JD QD KD], card_counts: { 1 => 10, 2 => 10, 3 => 10 })
      no_pass = after_pass.merge(pass_direction: :none, own_pass: [], received_cards: [])

      %i[mellem svaer].each do |level|
        assert_equal "KD", bot(level).choose_play(no_pass), level
        refute_includes %w[JD QD KD], bot(level).choose_play(after_pass), level
      end
    end

    test "Svær keeps its hearts in the pass with a moon hand" do
      pass = bot(:svaer).choose_pass(%w[AH KH QH JH TH 9H 2C 3C 4D AS KS 5S 6S])

      assert_empty pass.select { |code| code.end_with?("H") }
    end

    test "Svær won't push a seat over the end score with Q♠ while it is not lowest" do
      # Seat 3 led the heart and wins the stik.
      view = view(legal: %w[QS 9C 2D], trick: %w[5H], hand: %w[QS 9C 2D 3D])

      assert_equal "9C", bot(:svaer).choose_play(view, totals: [ 50, 20, 30, 95 ], end_score: 100)
      assert_equal "QS", bot(:svaer).choose_play(view, totals: [ 10, 20, 30, 95 ], end_score: 100)
    end

    # ── Every level ─────────────────────────────────────────────────────

    test "every level passes and plays many seeded runder without an illegal move" do
      Bot::LEVELS.each do |level|
        player = Bot.new(level:, random: Random.new(3))
        60.times do |seed|
          round = Round.new(rules: Rules.new(jack_of_diamonds_minus_ten: seed.odd?), deal: Deal.shuffled(shuffler: Random.new(seed)), pass_direction: :left)
          (0..3).each do |seat|
            pass = player.choose_pass(round.view_for(seat))
            result = round.apply(seat, Pass.new(cards: pass))
            assert result.accepted?, "#{level}, seed #{seed}: seat #{seat} passed #{pass}: #{result.reason}"
            round = result.round
          end

          until round.complete?
            seat = round.to_act
            card = player.choose_play(round.view_for(seat), totals: [ 40, 60, 80, 90 ], end_score: 100)
            result = round.apply(seat, Play.new(card:))
            assert result.accepted?, "#{level}, seed #{seed}: seat #{seat} played #{card}: #{result.reason}"
            round = result.round
          end
        end
      end
    end

    test "the same seed gives the same choices" do
      runs = 2.times.map do
        player = Bot.new(level: :mellem, random: Random.new(9))
        round = Round.new(rules: Rules.standard, deal: Deal.shuffled(shuffler: Random.new(1)))
        until round.complete?
          round = round.apply(round.to_act, Play.new(card: player.choose_play(round.view_for(round.to_act)))).round
        end
        round.plays_string
      end

      assert_equal runs.first, runs.last
    end

    test "rejects an unknown level" do
      assert_raises(ArgumentError) { Bot.new(level: :expert) }
    end

    test "a moon shooter who leads gives 26 to the others; otherwise takes −26" do
      player = bot(:mellem)
      assert_equal "add_to_others", player.choose_moon(seat: 0, totals: [ 10, 40, 30, 20 ])
      assert_equal "add_to_others", player.choose_moon(seat: 0, totals: [ 0, 0, 0, 0 ])
      assert_equal "subtract_from_self", player.choose_moon(seat: 1, totals: [ 10, 40, 30, 20 ])
    end

    private

    # A view as Round#view_for shows it to seat 0, with what the bot reads.
    # The stik so far was played by the seats before seat 0.
    def view(legal:, trick:, hand: legal, tricks: [], rules: Rules.standard)
      seats = (4 - trick.size...4).to_a
      {
        seat: 0,
        hand:,
        legal_moves: legal,
        current_trick: trick.each_with_index.map { |card, index| { seat: seats[index], card: } },
        tricks:,
        rules: rules.to_h,
        hearts_broken: tricks.any? { |done| done[:plays].any? { |play| play[:card].end_with?("H") } },
        pass_direction: :left,
        own_pass: []
      }
    end

    def trick(cards, leader:, winner:)
      { plays: cards.each_with_index.map { |card, index| { seat: (leader + index) % 4, card: } }, winner: }
    end

    # Four clean stik: clubs and diamonds, won by seat 1 (nobody is void).
    def four_tricks
      [ trick(%w[2C 6C 7C 8C], leader: 1, winner: 1), trick(%w[KD 2D 3D 4D], leader: 1, winner: 1),
        trick(%w[QD 5D 6D TD], leader: 1, winner: 1), trick(%w[JC 3C 5C TC], leader: 1, winner: 1) ]
    end
  end
end
