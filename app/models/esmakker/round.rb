module Esmakker
  # One runde of es-makker: the deal (four hands and the kitty), who deals,
  # and the append-only log of what the seats did (Action). Immutable:
  # #apply returns a Result holding the next Round, with the action
  # appended to the log.
  #
  # So far (ticket 02) a runde is its meldingsrunde (Bidding): the intents
  # are the bidding's (Bid, Pas, DetKanJegSelv, GaaMed, ClaimJernhaand),
  # each logged as one token (Round.token). Which seats may claim a
  # jernhånd follows from the hands (Jernhaand). The bidding ends in one of
  # two ways:
  #
  # - a melder with a melding: phase :declaring, where trump and the called
  #   ace come next (ticket 03), so nobody is to act yet;
  # - a redeal (phase :redeal): everybody passed, and the former forhånd
  #   deals (A7), or a jernhånd was claimed, and the same kortgiver deals
  #   again, so the same seat keeps the forhånd (A6). #next_dealer says who
  #   deals it. A redealt runde never completes and scores nothing; the spil
  #   deals the runde again as its next round row (Game#deal_next!).
  class Round
    # The most steps (log entries) a runde can take, so the spil's version
    # grows across runder (Game#version).
    MAX_STEPS = 1000

    # The log token of each intent without data; a Bid is its melding's code
    # ("9", "10halve", "sol"), which never looks like one of these.
    TOKENS = {
      Bidding::Pas => "pas",
      Bidding::DetKanJegSelv => "selv",
      Bidding::GaaMed => "med",
      Bidding::ClaimJernhaand => "jernhaand"
    }.freeze
    BIDDING_INTENTS = [ Bidding::Bid, *TOKENS.keys ].freeze

    attr_reader :rules, :deal, :dealer, :actions, :bidding

    # Rebuilds a round from its stored form: the deal (55 card codes), the
    # kortgiver's seat and the action log ("seat:token" entries). Raises
    # ArgumentError on corrupt data, e.g. an action this runde cannot take.
    def self.from_strings(rules:, deal:, dealer:, actions: "")
      new(rules:, deal: Deal.parse(deal), dealer:, actions: Action.parse_log(actions))
    end

    # The token an intent is logged as.
    def self.token(intent) = intent.is_a?(Bidding::Bid) ? intent.melding.to_s : TOKENS.fetch(intent.class)

    # The intent a logged token stands for. Raises ArgumentError on a token
    # that is none.
    def self.intent(token)
      kind = TOKENS.key(token)
      kind ? kind.new : Bidding::Bid.new(melding: Melding.parse(token))
    end

    # Raises ArgumentError when an action is not legal at its point.
    def initialize(rules:, deal:, dealer:, actions: [])
      raise ArgumentError, "the kortgiver is a seat 0–3" unless Seats::ALL.include?(dealer)

      @rules = rules
      @deal = deal
      @dealer = dealer
      @actions = actions.dup.freeze
      @bidding = Bidding.new(ladder: Ladder.new(pahaeng_order: rules.pahaeng_order), forhand:, jernhaand_seats:,
                             actions: @actions.map { |action| [ action.seat, Round.intent(action.token) ] })
      freeze
    end

    def forhand = Seats.forhand(dealer)

    # Who deals the next round row: after a redeal the bidding says (the
    # former forhånd, or the same kortgiver after a jernhånd); otherwise the
    # kortgiver moves one seat clockwise.
    def next_dealer = redeal? ? outcome.dealer : Seats.next_dealer(dealer)

    # The meldingsrunde's ending (Bidding::Outcome), or nil while it runs.
    def outcome = bidding.outcome

    def redeal? = outcome&.redeal? || false

    # :bidding, then :declaring (a melder; trump and ace come in ticket 03)
    # or :redeal.
    def phase
      return :bidding unless bidding.complete?

      redeal? ? :redeal : :declaring
    end

    # Es-makker has no bytning; the bord asks every engine (Table::Playing).
    def passing? = false

    def complete? = false

    # The seat to act now: the bidding's, nobody once it is over.
    def to_act = phase == :bidding ? bidding.to_act : nil
    def seats_to_act = [ to_act ].compact

    # The seats whose hand is a jernhånd, whether or not they claim it.
    def jernhaand_seats = Seats::ALL.select { |seat| Jernhaand.hand?(deal.hand(seat)) }

    # Runde points per seat; empty until the runde is complete.
    def points = []

    # Grows with every action (Game#version).
    def steps = actions.size

    def deal_string = deal.to_s
    def actions_string = Action.log_string(actions)

    # The columns the runde's row stores (Round, the ActiveRecord model).
    def stored = { actions: actions_string }

    # A bidding intent, judged by the bidding; anything else is rejected.
    def apply(seat, intent)
      return Result.rejected(:unknown_intent) unless BIDDING_INTENTS.any? { |kind| intent.is_a?(kind) }

      result = bidding.apply(seat, intent)
      return Result.rejected(result.reason) if result.rejected?

      Result.accepted(Round.new(rules:, deal:, dealer:, actions: [ *actions, Action.new(seat:, token: Round.token(intent)) ]))
    end

    # Everything the seat may know about the runde: its own hand, how many
    # cards the others and the kitty hold (never which), who deals and who
    # is forhånd, the whole bidding (it is public) and what the seat may
    # choose in it now (#choices).
    def view_for(seat)
      {
        seat:,
        phase:,
        hand: in_display_order(deal.hand(seat)),
        card_counts: (Seats::ALL - [ seat ]).to_h { |other| [ other, deal.hand(other).size ] },
        kitty_count: deal.kitty.size,
        dealer:,
        forhand:,
        to_act:,
        bidding: bidding.view.except(:ladder, :jernhaand_claimable),
        choices: choices(seat)
      }
    end

    # What the seat may choose now (Bidding#legal_intents): the meldinger it
    # may bid (codes, lowest first), and whether it may say "det kan jeg
    # selv", gå med, pas, or claim a jernhånd.
    def choices(seat)
      legal = bidding.legal_intents(seat)
      {
        meldinger: legal.grep(Bidding::Bid).map { |bid| bid.melding.to_s },
        det_kan_jeg_selv: legal.include?(Bidding::DetKanJegSelv.new),
        gaa_med: legal.include?(Bidding::GaaMed.new),
        pas: legal.include?(Bidding::Pas.new),
        jernhaand: legal.include?(Bidding::ClaimJernhaand.new)
      }
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
