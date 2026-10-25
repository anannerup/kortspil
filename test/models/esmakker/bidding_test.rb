require "test_helper"

module Esmakker
  # The meldingsrunde (REGLER §2.0). Seats are 0–3 clockwise; seat 0 is the
  # forhånd unless a test says otherwise.
  class BiddingTest < ActiveSupport::TestCase
    PAS = Bidding::Pas.new
    SELV = Bidding::DetKanJegSelv.new
    GAA_MED = Bidding::GaaMed.new
    JERNHAAND = Bidding::ClaimJernhaand.new

    test "the forhånd opens and may bid any melding on the ladder or pas" do
      bidding = start

      assert_equal 0, bidding.to_act
      assert_equal [ *bids(Ladder.standard.meldinger), PAS ], bidding.legal_intents(0)
      assert_equal [], bidding.legal_intents(1)
    end

    test "after a bid the next seat must pas or bid higher" do
      bidding = act(start, [ 0, "9vip" ])

      assert_equal 1, bidding.to_act
      assert_equal [ *bids(Ladder.standard.above(m("9vip"))), PAS ], bidding.legal_intents(1)
      assert_rejected :not_higher, bidding.apply(1, bid("9"))
      assert_rejected :not_higher, bidding.apply(1, bid("9vip"))
    end

    test "a full duel with repeated det kan jeg selv" do
      bidding = act(start, [ 0, "9" ], [ 1, "10" ])

      assert_equal 0, bidding.to_act
      assert_equal 0, bidding.serveret
      assert_equal [ SELV, PAS ], bidding.legal_intents(0)

      bidding = act(bidding, [ 0, SELV ])
      assert_equal [ 0, m("10") ], [ bidding.holder, bidding.melding ]
      assert_equal 1, bidding.to_act

      bidding = act(bidding, [ 1, "11gode" ], [ 0, SELV ], [ 1, "12" ], [ 0, SELV ])
      assert_equal [ 0, m("12"), 1 ], [ bidding.holder, bidding.melding, bidding.to_act ]

      bidding = act(bidding, [ 1, PAS ])
      assert_equal 2, bidding.to_act
      assert_equal [ 0, m("12") ], [ bidding.holder, bidding.melding ]
      assert_nil bidding.serveret
    end

    test "det kan jeg selv takes over exactly the melding just bid" do
      bidding = act(start, [ 0, "8" ], [ 1, "11halve" ], [ 0, SELV ])

      assert_equal m("11halve"), bidding.melding
      assert_equal [ *bids(Ladder.standard.above(m("11halve"))), PAS ], bidding.legal_intents(1)
    end

    test "the serveret holder may not bid higher instead (A1)" do
      bidding = act(start, [ 0, "9" ], [ 1, "10" ])

      assert_rejected :det_kan_jeg_selv_or_pas, bidding.apply(0, bid("11"))
    end

    test "when the serveret holder passes, the challenger holds and the next seat challenges" do
      bidding = act(start, [ 0, "9" ], [ 1, "10" ], [ 0, PAS ])

      assert_equal [ 1, m("10"), 2 ], [ bidding.holder, bidding.melding, bidding.to_act ]
      assert_nil bidding.serveret
      assert_equal [ 0 ], bidding.passed
    end

    test "challenger passes, the next seat becomes the challenger against the holder" do
      bidding = act(start, [ 0, "9" ], [ 1, PAS ])

      assert_equal [ 0, 2 ], [ bidding.holder, bidding.to_act ]

      bidding = act(bidding, [ 2, "10" ], [ 0, SELV ], [ 2, PAS ])
      assert_equal [ 0, 3 ], [ bidding.holder, bidding.to_act ]
    end

    test "the bidding ends when all others have passed" do
      bidding = act(start, [ 0, "9" ], [ 1, "10" ], [ 0, SELV ], [ 1, PAS ], [ 2, PAS ], [ 3, PAS ])

      assert bidding.complete?
      assert_nil bidding.to_act
      assert_equal Bidding::Outcome.melder(0, m("10"), []), bidding.outcome
      assert_rejected :bidding_complete, bidding.apply(1, PAS)
      assert_equal [], bidding.legal_intents(0)
    end

    test "passed players are out for the rest of the runde" do
      bidding = act(start, [ 0, PAS ], [ 1, "8" ], [ 2, PAS ], [ 3, "9" ], [ 1, PAS ])

      assert bidding.complete?
      assert_equal 3, bidding.outcome.melder
      assert_equal [ 0, 2, 1 ], bidding.passed
    end

    test "a pass in the opening moves the turn on, and the last seat may still bid" do
      bidding = act(start(forhand: 2), [ 2, PAS ], [ 3, PAS ], [ 0, PAS ])

      assert_equal 1, bidding.to_act
      bidding = act(bidding, [ 1, "8" ])
      assert_equal Bidding::Outcome.melder(1, m("8"), []), bidding.outcome
    end

    test "all four pass: a redeal, and the former forhånd deals it" do
      bidding = act(start(forhand: 2), [ 2, PAS ], [ 3, PAS ], [ 0, PAS ], [ 1, PAS ])

      assert bidding.outcome.redeal?
      assert_equal :all_passed, bidding.outcome.reason
      assert_equal 2, bidding.outcome.dealer
      assert_equal 1, bidding.dealer
    end

    test "gå med on sol: several players go with, in order" do
      bidding = act(start, [ 0, "sol" ])

      assert_includes bidding.legal_intents(1), GAA_MED
      bidding = act(bidding, [ 1, GAA_MED ], [ 2, PAS ], [ 3, GAA_MED ])

      assert_equal Bidding::Outcome.melder(0, m("sol"), [ 1, 3 ]), bidding.outcome
    end

    test "det kan jeg selv on sol, and the challenger may then go with" do
      bidding = act(start, [ 0, "9" ], [ 1, "sol" ])

      assert_equal [ SELV, GAA_MED, PAS ], bidding.legal_intents(0)
      bidding = act(bidding, [ 0, SELV ])

      assert_equal [ 0, m("sol"), 1 ], [ bidding.holder, bidding.melding, bidding.to_act ]
      assert_includes bidding.legal_intents(1), GAA_MED
      bidding = act(bidding, [ 1, GAA_MED ], [ 2, PAS ], [ 3, PAS ])

      assert_equal Bidding::Outcome.melder(0, m("sol"), [ 1 ]), bidding.outcome
    end

    test "the serveret holder may go with the challenger's sol-melding, who then holds it (A5)" do
      bidding = act(start, [ 0, "9" ], [ 1, "ren_sol" ], [ 0, GAA_MED ], [ 2, PAS ], [ 3, PAS ])

      assert_equal Bidding::Outcome.melder(1, m("ren_sol"), [ 0 ]), bidding.outcome
    end

    test "going with gives up further bidding, and a melding bid over voids it (§2.7 example 1)" do
      bidding = act(start, [ 0, "sol" ], [ 1, GAA_MED ], [ 2, "10vip" ])

      assert_equal 0, bidding.to_act
      assert_equal [], bidding.went_with
      bidding = act(bidding, [ 0, SELV ], [ 2, PAS ], [ 3, PAS ])

      assert_equal Bidding::Outcome.melder(0, m("10vip"), []), bidding.outcome
    end

    test "gå med works on every sol melding and only on sol-melding" do
      %w[sol ren_sol bordlaegger ren_bordlaegger].each do |code|
        assert_includes act(start, [ 0, code ]).legal_intents(1), GAA_MED, code
      end
      assert_rejected :not_sol_melding, act(start, [ 0, "9vip" ]).apply(1, GAA_MED)
      assert_rejected :not_sol_melding, start.apply(0, GAA_MED)
    end

    test "det kan jeg selv works on bordlægger" do
      bidding = act(start, [ 0, "11" ], [ 1, "bordlaegger" ], [ 0, SELV ], [ 1, PAS ], [ 2, GAA_MED ], [ 3, PAS ])

      assert_equal Bidding::Outcome.melder(0, m("bordlaegger"), [ 2 ]), bidding.outcome
    end

    test "the challenger at the top of the ladder can only pas" do
      bidding = act(start, [ 0, "12" ], [ 1, "13vip" ], [ 0, SELV ])

      assert_equal [ PAS ], bidding.legal_intents(1)
    end

    test "a jernhånd may be claimed before the first bid, out of turn: a redeal by the same kortgiver" do
      bidding = act(start(forhand: 1, jernhaand_seats: [ 3 ]), [ 1, PAS ])

      assert_equal [ JERNHAAND ], bidding.legal_intents(3)
      bidding = act(bidding, [ 3, JERNHAAND ])

      assert_equal Bidding::Outcome.redeal(:jernhaand, 0), bidding.outcome
    end

    test "no jernhånd claim after the first bid or without a jernhånd" do
      bidding = start(jernhaand_seats: [ 2 ])

      assert_rejected :no_jernhaand, bidding.apply(1, JERNHAAND)
      assert_rejected :bidding_started, act(bidding, [ 0, "8" ]).apply(2, JERNHAAND)
      assert_not_includes act(bidding, [ 0, "8" ]).legal_intents(2), JERNHAAND
    end

    test "invalid intents are rejected with reasons" do
      bidding = act(start, [ 0, "9" ])

      assert_rejected :not_your_turn, bidding.apply(2, PAS)
      assert_rejected :not_your_turn, bidding.apply(7, PAS)
      assert_rejected :nothing_to_take_over, bidding.apply(1, SELV)
      assert_rejected :not_on_ladder, bidding.apply(1, Bidding::Bid.new(melding: "10"))
      assert_rejected :not_on_ladder, act(start(ladder: Ladder.new(pahaeng_order: %i[vip])), [ 0, "9" ]).apply(1, bid("10halve"))
      assert_rejected :unknown_intent, bidding.apply(1, :pas)
    end

    test "the view shows the public bidding" do
      view = act(start, [ 0, "9" ], [ 1, "sol" ]).view

      assert_equal :bidding, view[:phase]
      assert_equal "sol", view[:melding]
      assert_equal [ 1, 0, 0 ], [ view[:holder], view[:serveret], view[:to_act] ]
      assert_equal [ { seat: 0, action: :bid, melding: "9" }, { seat: 1, action: :bid, melding: "sol" } ], view[:history]
      assert_equal "9", view[:ladder][4]
      assert_nil view[:outcome]
    end

    test "replaying the actions rebuilds the same state, and illegal stored actions raise" do
      bidding = act(start, [ 0, "9" ], [ 1, "10" ], [ 0, SELV ], [ 1, PAS ])
      replayed = Bidding.new(ladder: Ladder.standard, forhand: 0, actions: bidding.actions)

      assert_equal bidding.view, replayed.view
      assert_raises(ArgumentError) { Bidding.new(ladder: Ladder.standard, forhand: 0, actions: [ [ 1, PAS ] ]) }
    end

    test "random legal play always ends in a valid outcome, and exactly the legal intents are accepted" do
      random = Random.new(2026)
      orders = [ Ladder::DEFAULT_PAHAENG_ORDER, %i[gode halve vip], %i[vip], [] ]
      endings = []

      300.times do
        ladder = Ladder.new(pahaeng_order: orders.sample(random:))
        bidding = start(ladder:, forhand: random.rand(4), jernhaand_seats: random.rand < 0.1 ? [ random.rand(4) ] : [])
        candidates = [ PAS, SELV, GAA_MED, JERNHAAND, *bids(ladder.meldinger) ]

        200.times do
          break if bidding.complete?

          Bidding::SEATS.each do |seat|
            legal = bidding.legal_intents(seat)
            candidates.each { |intent| assert_equal legal.include?(intent), bidding.apply(seat, intent).accepted? }
          end
          seat = Bidding::SEATS.select { |other| bidding.legal_intents(other).any? }.sample(random:)
          legal = bidding.legal_intents(seat)
          # Pas half the time, so all-pass redeals happen too.
          intent = legal.include?(PAS) && random.rand < 0.5 ? PAS : legal.sample(random:)
          bidding = bidding.apply(seat, intent).bidding
        end

        assert bidding.complete?, "bidding did not end: #{bidding.history}"
        assert_valid_outcome bidding
        endings << [ bidding.outcome.kind, bidding.outcome.reason, bidding.outcome.went_with.any? ]
      end

      assert_equal 4, endings.uniq.size, "the random runs should reach every kind of ending"
    end

    private

    def start(ladder: Ladder.standard, forhand: 0, jernhaand_seats: [])
      Bidding.start(ladder:, forhand:, jernhaand_seats:)
    end

    def m(code) = Melding.parse(code)
    def bid(code) = Bidding::Bid.new(melding: m(code))
    def bids(meldinger) = meldinger.map { |melding| Bidding::Bid.new(melding:) }

    # Each step is [seat, intent], where a string intent is a melding code to bid.
    def act(bidding, *steps)
      steps.reduce(bidding) do |current, (seat, intent)|
        intent = bid(intent) if intent.is_a?(String)
        result = current.apply(seat, intent)
        assert result.accepted?, "seat #{seat} #{intent.inspect} rejected: #{result.reason}"
        result.bidding
      end
    end

    def assert_rejected(reason, result)
      assert result.rejected?
      assert_equal reason, result.reason
      assert_nil result.bidding
    end

    def assert_valid_outcome(bidding)
      outcome = bidding.outcome
      return assert(outcome.reason == :jernhaand || bidding.passed.sort == Bidding::SEATS) if outcome.redeal?

      assert bidding.ladder.include?(outcome.melding)
      assert_not_includes bidding.passed, outcome.melder
      assert_not_includes outcome.went_with, outcome.melder
      assert_empty outcome.went_with if outcome.melding.stik?
      assert_empty outcome.went_with & bidding.passed
      others = Bidding::SEATS - [ outcome.melder ]
      assert others.all? { |seat| bidding.passed.include?(seat) || bidding.history.any? { |entry| entry[:seat] == seat && entry[:action] == :gaa_med } }
    end
  end
end
