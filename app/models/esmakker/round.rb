module Esmakker
  # One runde of es-makker: the deal (four hands and the kitty), who deals,
  # and the append-only log of what the seats did (Action). Immutable:
  # #apply returns a Result holding the next Round, with the action
  # appended to the log.
  #
  # A runde starts with its meldingsrunde (Bidding): the intents are the
  # bidding's (Bid, Pas, DetKanJegSelv, GaaMed, ClaimJernhaand). Which
  # seats may claim a jernhånd follows from the hands (Jernhaand). The
  # bidding ends in one of two ways:
  #
  # - a melder with a melding. A stik melding without påhæng, with gode,
  #   halve or vip is then played (Play, tickets 03, 04, 06 and 07): the
  #   melder names trump, calls an ace, takes the kitty and lays three cards
  #   away (at halve the ace holder names trump and takes the kitty; at vip
  #   the melder calls the ace and then turns the kitty's cards for trump),
  #   may lay a card fordækt, and the 13 stik are played (ChooseTrump,
  #   CallAce, TurnCard, AcceptTrump, Bank, CloseBankWindow, Discard,
  #   LayFordaekt, PlayCard; at vip the bank window comes after trump). Sol
  #   and ren sol are played by SolPlay (ticket 09): the melder and those
  #   who went with exchange with the kitty in turn (Discard) and the
  #   forhånd leads (PlayCard). Bordlægger and ren bordlægger are not built
  #   yet: the runde is complete at once, not played (RundeResult), and the
  #   spil goes on.
  # - a redeal (phase :redeal): everybody passed, and the former forhånd
  #   deals (A7), or a jernhånd was claimed, and the same kortgiver deals
  #   again, so the same seat keeps the forhånd (A6). #next_dealer says who
  #   deals it. A redealt runde never completes and scores nothing; the spil
  #   deals the runde again as its next round row (Game#deal_next!).
  #
  # Every intent is logged as one token (Round.token): a melding's code,
  # "pas", "selv", "med", "jernhaand"; then "trumfH" / "trumfloes", "esD",
  # at vip "vend" and "accepter", "bank" and "bankslut" (the bank window
  # closed), "kast-2C-3D-X1", "fordaekt-3S" and each
  # card played by its code.
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
      Bidding::ClaimJernhaand => "jernhaand",
      TurnCard => "vend",
      AcceptTrump => "accepter",
      Bank => "bank",
      CloseBankWindow => "bankslut"
    }.freeze
    BIDDING_INTENTS = [ Bidding::Bid, Bidding::Pas, Bidding::DetKanJegSelv, Bidding::GaaMed, Bidding::ClaimJernhaand ].freeze
    PLAY_INTENTS = Play::INTENTS
    TRUMP_TOKEN = /\Atrumf(.+)\z/
    ACE_TOKEN = /\Aes([A-Z])\z/
    DISCARD_TOKEN = /\Akast-(.+)\z/
    FORDAEKT_TOKEN = /\Afordaekt-(.+)\z/

    attr_reader :rules, :deal, :dealer, :actions, :bidding, :play

    # Rebuilds a round from its stored form: the deal (55 card codes), the
    # kortgiver's seat and the action log ("seat:token" entries). Raises
    # ArgumentError on corrupt data, e.g. an action this runde cannot take.
    def self.from_strings(rules:, deal:, dealer:, actions: "")
      new(rules:, deal: Deal.parse(deal), dealer:, actions: Action.parse_log(actions))
    end

    # The token an intent is logged as.
    def self.token(intent)
      case intent
      when Bidding::Bid then intent.melding.to_s
      when ChooseTrump then "trumf#{intent.trump}"
      when CallAce then "es#{intent.suit}"
      when Discard then "kast-#{intent.cards.join('-')}"
      when LayFordaekt then "fordaekt-#{intent.card}"
      when PlayCard then intent.card.to_s
      else TOKENS.fetch(intent.class)
      end
    end

    # The intent a logged token stands for. Raises ArgumentError on a token
    # that is none.
    def self.intent(token)
      kind = TOKENS.key(token)
      return kind.new if kind
      return PlayCard.new(card: Card.parse(token)) if Card.valid?(token)
      return ChooseTrump.new(trump: Trump.parse(token[TRUMP_TOKEN, 1])) if token.match?(TRUMP_TOKEN)
      return CallAce.new(suit: token[ACE_TOKEN, 1]) if token.match?(ACE_TOKEN)
      return Discard.new(cards: token[DISCARD_TOKEN, 1].split("-").map { |code| Card.parse(code) }) if token.match?(DISCARD_TOKEN)
      return LayFordaekt.new(card: Card.parse(token[FORDAEKT_TOKEN, 1])) if token.match?(FORDAEKT_TOKEN)

      Bidding::Bid.new(melding: Melding.parse(token))
    end

    # Whether the intent belongs to the meldingsrunde.
    def self.bidding_intent?(intent) = BIDDING_INTENTS.any? { |kind| intent.is_a?(kind) }

    # Raises ArgumentError when an action is not legal at its point.
    def initialize(rules:, deal:, dealer:, actions: [])
      raise ArgumentError, "the kortgiver is a seat 0–3" unless Seats::ALL.include?(dealer)

      @rules = rules
      @deal = deal
      @dealer = dealer
      @actions = actions.dup.freeze
      intents = @actions.map { |action| [ action.seat, Round.intent(action.token) ] }
      split = intents.index { |_seat, intent| !Round.bidding_intent?(intent) } || intents.size
      @bidding = Bidding.new(ladder: Ladder.new(pahaeng_order: rules.pahaeng_order), forhand:, jernhaand_seats:, actions: intents.first(split))
      @play = start_play(intents.drop(split))
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

    # :bidding; then :redeal, or the play's phases (:choosing_trump,
    # :calling_ace, :turning, at vip :banking, :discarding, at a sol-melding
    # :exchanging; :playing) and :complete. A melding not
    # played yet (RundeResult :not_played) is :complete at once.
    def phase
      return :bidding unless bidding.complete?
      return :redeal if redeal?

      play ? play.phase : :complete
    end

    # Es-makker has no bytning; the bord asks every engine (Table::Playing).
    def passing? = false

    def complete? = phase == :complete

    # Whether vip's bank window is open (Play#banking?).
    def banking? = phase == :banking

    # The seat to act now: the bidding's, then the play's.
    def to_act
      return bidding.to_act if phase == :bidding

      play&.to_act
    end

    def seats_to_act = [ to_act ].compact

    # The seats whose hand is a jernhånd, whether or not they claim it.
    def jernhaand_seats = Seats::ALL.select { |seat| Jernhaand.hand?(deal.hand(seat)) }

    # How the runde ended (RundeResult), once it is complete.
    def result
      return nil unless complete?

      play ? play.result : RundeResult.not_played(melder: outcome.melder, melding: outcome.melding)
    end

    # Runde points per seat; empty until the runde is complete.
    def points = result&.points || []

    # Grows with every action (Game#version).
    def steps = actions.size

    def deal_string = deal.to_s
    def actions_string = Action.log_string(actions)

    # The columns the runde's row stores (Round, the ActiveRecord model).
    def stored = { actions: actions_string }

    # A bidding intent is the bidding's to judge, the rest the play's.
    def apply(seat, intent)
      result = judge(seat, intent)
      return Result.rejected(result.reason) if result.rejected?

      Result.accepted(Round.new(rules:, deal:, dealer:, actions: [ *actions, Action.new(seat:, token: Round.token(intent)) ]))
    end

    # What a seat that has to act without choosing does (a bot standing in
    # for a player who forlod): pas in the meldingsrunde, then the play's
    # default (Play#default_intent). Nil when the seat is not to act.
    def default_intent(seat)
      return nil unless seat == to_act

      phase == :bidding ? Bidding::Pas.new : play.default_intent(seat)
    end

    # Everything the seat may know about the runde: its own hand, how many
    # cards the others and the kitty hold (never which), who deals and who
    # is forhånd, the whole bidding (it is public), what the seat may
    # choose now (#choices), the play as the seat may see it (Play#view_for;
    # nil until it starts) and the runde's result once complete.
    def view_for(seat)
      {
        seat:,
        phase:,
        hand: in_display_order(hand(seat)),
        card_counts: (Seats::ALL - [ seat ]).to_h { |other| [ other, hand(other).size ] },
        kitty_count: play&.kitty_taken? ? 0 : deal.kitty.size,
        dealer:,
        forhand:,
        to_act:,
        bidding: bidding.view.except(:ladder, :jernhaand_claimable),
        choices: choices(seat),
        play: play&.view_for(seat),
        result: result&.to_h
      }
    end

    # What the seat may choose now: in the meldingsrunde
    # (Bidding#legal_intents) the meldinger it may bid (codes, lowest
    # first), and whether it may say "det kan jeg selv", gå med, pas, or
    # claim a jernhånd; in the play (Play#legal_intents) the trumps it may
    # name, the aces it may call, at vip whether it may turn the kitty's
    # next card or take the last one turned as trump, whether it is offered
    # "Bank" (the same to the three seats but the melder's before the first
    # bank, Play#bank_offered?), whether it is to lay cards away (three, or
    # at a sol-melding as many as it took up), the cards it may lay fordækt,
    # and the cards it may play.
    def choices(seat)
      legal = bidding.legal_intents(seat)
      play_legal = play ? play.legal_intents(seat) : []
      {
        meldinger: legal.grep(Bidding::Bid).map { |bid| bid.melding.to_s },
        det_kan_jeg_selv: legal.include?(Bidding::DetKanJegSelv.new),
        gaa_med: legal.include?(Bidding::GaaMed.new),
        pas: legal.include?(Bidding::Pas.new),
        jernhaand: legal.include?(Bidding::ClaimJernhaand.new),
        trumps: play_legal.grep(ChooseTrump).map { |choice| choice.trump.to_s },
        aces: play_legal.grep(CallAce).map(&:suit),
        turn_card: play_legal.include?(TurnCard.new),
        accept_trump: play_legal.include?(AcceptTrump.new),
        bank: play_legal.include?(Bank.new),
        discard: %i[discarding exchanging].include?(phase) && seat == to_act,
        fordaekt: play_legal.grep(LayFordaekt).map { |choice| choice.card.to_s }
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

    # The seat's cards now: the deal's, then the play's.
    def hand(seat) = play ? play.hand(seat) : deal.hand(seat)

    def judge(seat, intent)
      return bidding.apply(seat, intent) if Round.bidding_intent?(intent)
      return Result.rejected(:unknown_intent) unless PLAY_INTENTS.any? { |kind| intent.is_a?(kind) }
      return Result.rejected(phase == :complete ? :round_complete : :not_now) unless play

      play.apply(seat, intent)
    end

    # The play once the bidding has a melder whose melding is played here
    # (Play for a stik melding, SolPlay for sol and ren sol); nil otherwise.
    # Play intents before that are corrupt data.
    def start_play(intents)
      outcome = bidding.outcome
      melding = outcome&.melding
      if melding && Play.plays?(melding)
        return Play.new(rules:, deal:, melder: outcome.melder, melding:, actions: intents)
      end
      if melding && SolPlay.plays?(melding)
        return SolPlay.new(rules:, deal:, melder: outcome.melder, melding:, forhand:, went_with: outcome.went_with, actions: intents)
      end
      raise ArgumentError, "play actions without a melding to play" if intents.any?

      nil
    end

    # Hands in display order; once a sol-melding is won, with the ace as
    # the lowest card (SolPlay.display_key).
    def in_display_order(cards)
      sol = outcome&.melding&.sol_melding?
      cards.sort_by { |card| sol ? SolPlay.display_key(card) : card.display_key }.map(&:to_s)
    end
  end
end
