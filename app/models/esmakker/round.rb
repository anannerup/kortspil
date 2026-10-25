module Esmakker
  # One runde of es-makker: the deal (four hands and the kitty), who deals,
  # and the append-only log of what the seats did (Action). Immutable:
  # #apply returns a Result holding the next Round, with the action
  # appended to the log.
  #
  # So far (ticket 01) a runde is only dealt: the meldingsrunde is next and
  # comes as intents in ticket 02, so every intent is rejected and the log
  # stays empty. Nobody is to act yet, so no tur-ur runs.
  class Round
    # The most steps (log entries) a runde can take, so the spil's version
    # grows across runder (Game#version).
    MAX_STEPS = 1000

    attr_reader :rules, :deal, :dealer, :actions

    # Rebuilds a round from its stored form: the deal (55 card codes), the
    # kortgiver's seat and the action log ("seat:token" entries). Raises
    # ArgumentError on corrupt data, e.g. an action this runde cannot take.
    def self.from_strings(rules:, deal:, dealer:, actions: "")
      round = new(rules:, deal: Deal.parse(deal), dealer:)
      Action.parse_log(actions).reduce(round) { |before, action| before.replay(action) }
    end

    def initialize(rules:, deal:, dealer:, actions: [])
      raise ArgumentError, "the kortgiver is a seat 0–3" unless Seats::ALL.include?(dealer)

      @rules = rules
      @deal = deal
      @dealer = dealer
      @actions = actions.dup.freeze
      freeze
    end

    def forhand = Seats.forhand(dealer)
    def next_dealer = Seats.next_dealer(dealer)

    # The meldingsrunde comes next (ticket 02).
    def phase = :bidding

    def complete? = false

    # The seat to act now: nobody until the meldingsrunde is built.
    def to_act = nil
    def seats_to_act = [ to_act ].compact

    # Runde points per seat; empty until the runde is complete.
    def points = []

    # Grows with every action (Game#version).
    def steps = actions.size

    def deal_string = deal.to_s
    def actions_string = Action.log_string(actions)

    # The columns the runde's row stores (Round, the ActiveRecord model).
    def stored = { actions: actions_string }

    # Every intent is rejected until the meldingsrunde is built.
    def apply(_seat, _intent) = Result.rejected(:unknown_intent)

    # Everything the seat may know about the runde: its own hand, how many
    # cards the others and the kitty hold (never which), who deals and who
    # is forhånd.
    def view_for(seat)
      {
        seat:,
        phase:,
        hand: in_display_order(deal.hand(seat)),
        card_counts: (Seats::ALL - [ seat ]).to_h { |other| [ other, deal.hand(other).size ] },
        kitty_count: deal.kitty.size,
        dealer:,
        forhand:,
        to_act:
      }
    end

    # The runde one stored action later. Used only while rebuilding from
    # the log: an action the runde would not accept is corrupt data.
    def replay(action)
      raise ArgumentError, "action #{action} cannot be replayed: no intents are built yet"
    end

    def ==(other)
      other.is_a?(Round) && state == other.state
    end
    alias eql? ==

    def hash = state.hash

    protected

    def state = [ rules, deal, dealer, actions ]

    private

    def in_display_order(cards) = cards.sort_by(&:display_key).map(&:to_s)
  end
end
