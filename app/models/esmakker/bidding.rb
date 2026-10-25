module Esmakker
  # The meldingsrunde of one runde (REGLER §2.0 "Meldingsrunden og 'det kan
  # jeg selv'"). Immutable: #apply returns a Result holding the next
  # Bidding. Seats are 0–3 clockwise; the forhånd opens. The bidding is
  # public, so #view is the same for every seat.
  #
  # It is stored as its actions, [[seat, intent], ...], and rebuilt by
  # replaying them, like Hjerterfri::Round replays its plays.
  #
  # The flow, as read from §2.0 (the open details are listed under
  # "Antagelser" in .scratch/esmakker/issues/02-meldingsrunde.md):
  #
  # - Opening: from the forhånd clockwise, each seat bids a melding or says
  #   pas until someone bids. All four pass: a redeal, which the former
  #   forhånd deals (A7).
  # - Duel: the bidder holds the melding; the next active seat clockwise is
  #   the challenger, who bids higher or says pas.
  # - When the challenger bids higher, the turn goes back to the holder,
  #   who has serveretten: say "det kan jeg selv" (take over exactly the
  #   melding just bid) or pas. Assumption A1: the holder may not bid
  #   higher instead. After "det kan jeg selv" the challenger is to act
  #   again (A2). If the holder says pas, the challenger holds the melding.
  # - When the challenger says pas (or the holder does), the next active
  #   seat clockwise after the challenger becomes the new challenger
  #   against the holder (A3). Seats only move forward, so each seat
  #   challenges at most once.
  # - Passed seats are out for the rest of the runde, also after a pas in
  #   the opening (A4).
  # - On a sol melding, the seat to act may "gå med" instead of passing
  #   (the holder too, instead of "det kan jeg selv"): it is out of the
  #   bidding and plays the melding too, unless the melding is later bid
  #   over, in which case it simply stays out (A5).
  # - The bidding ends when no active seat is left to challenge: the holder
  #   is melder.
  # - A seat holding a jernhånd may claim it before the first bid, out of
  #   turn: a redeal by the same kortgiver (A6). Which seats hold one is
  #   the caller's to say (Jernhaand.hand?); the bidding never sees cards.
  class Bidding
    SEAT_COUNT = 4
    SEATS = (0...SEAT_COUNT).to_a.freeze

    attr_reader :ladder, :forhand, :jernhaand_seats, :actions, :melding, :holder, :to_act, :passed, :history, :outcome

    def self.start(ladder:, forhand:, jernhaand_seats: []) = new(ladder:, forhand:, jernhaand_seats:)

    # actions: [[seat, intent], ...] to replay. Raises ArgumentError when
    # one of them is not legal at its point.
    def initialize(ladder:, forhand:, jernhaand_seats: [], actions: [])
      raise ArgumentError, "forhånd must be a seat 0–3: #{forhand.inspect}" unless SEATS.include?(forhand)
      raise ArgumentError, "jernhånd seats must be seats 0–3" unless (jernhaand_seats - SEATS).empty?

      @ladder = ladder
      @forhand = forhand
      @jernhaand_seats = jernhaand_seats.uniq.sort.freeze
      @actions = actions.map { |seat, intent| [ seat, intent ].freeze }.freeze
      start_state
      @actions.each { |seat, intent| replay(seat, intent) }
      [ @passed, @went_with, @history ].each(&:freeze)
      freeze
    end

    def apply(seat, intent)
      reason = rejection(seat, intent)
      return Result.rejected(reason) if reason

      Result.accepted(Bidding.new(ladder:, forhand:, jernhaand_seats:, actions: [ *actions, [ seat, intent ] ]))
    end

    def complete? = !outcome.nil?
    def phase = complete? ? :complete : :bidding
    def dealer = (forhand - 1) % SEAT_COUNT

    # The seat that may say "det kan jeg selv" now (it is also to_act), or nil.
    def serveret = @serveret

    # Seats that went with the current melding, in the order they did.
    def went_with = @went_with.select { |_seat, melding| melding == self.melding }.map(&:first)

    # Every intent the seat may make now. Only to_act has turn intents; a
    # jernhånd claim needs no turn.
    def legal_intents(seat)
      return [] if complete?

      claims = rejection(seat, ClaimJernhaand.new) ? [] : [ ClaimJernhaand.new ]
      return claims unless seat == to_act

      turn = serveret ? [ DetKanJegSelv.new ] : ladder.above(melding).map { |higher| Bid.new(melding: higher) }
      turn << GaaMed.new if melding&.sol_melding?
      [ *claims, *turn, Pas.new ]
    end

    # Everything about the bidding; all of it is public.
    def view
      {
        phase:,
        forhand:,
        dealer:,
        to_act:,
        melding: melding&.to_s,
        holder:,
        serveret:,
        passed:,
        went_with:,
        jernhaand_claimable: jernhaand_seats.select { |seat| legal_intents(seat).include?(ClaimJernhaand.new) },
        history:,
        ladder: ladder.meldinger.map(&:to_s),
        outcome: outcome&.to_h
      }
    end

    private

    def start_state
      @melding = nil
      @holder = nil
      @challenger = nil
      @serveret = nil
      @to_act = forhand
      @passed = []
      @went_with = []
      @history = []
      @outcome = nil
    end

    def rejection(seat, intent)
      return :bidding_complete if complete?

      case intent
      when ClaimJernhaand then claim_rejection(seat)
      when Bid, Pas, DetKanJegSelv, GaaMed
        return :not_your_turn unless seat == to_act

        turn_rejection(intent)
      else :unknown_intent
      end
    end

    def claim_rejection(seat)
      return :bidding_started unless melding.nil?

      :no_jernhaand unless jernhaand_seats.include?(seat)
    end

    def turn_rejection(intent)
      case intent
      when Bid then bid_rejection(intent.melding)
      when DetKanJegSelv then :nothing_to_take_over unless serveret
      when GaaMed then :not_sol_melding unless melding&.sol_melding?
      end
    end

    def bid_rejection(bid)
      return :det_kan_jeg_selv_or_pas if serveret
      return :not_on_ladder unless bid.is_a?(Melding) && ladder.include?(bid)

      :not_higher unless melding.nil? || ladder.higher?(bid, melding)
    end

    def replay(seat, intent)
      reason = rejection(seat, intent)
      raise ArgumentError, "illegal bidding action by seat #{seat}: #{intent.inspect} (#{reason})" if reason

      case intent
      when ClaimJernhaand then @outcome = Outcome.redeal(:jernhaand, dealer)
      when Bid then replay_bid(seat, intent.melding)
      when DetKanJegSelv then replay_det_kan_jeg_selv(seat)
      when Pas then replay_pas(seat)
      when GaaMed then replay_gaa_med(seat)
      end
      @history << { seat:, action: action_name(intent), melding: melding&.to_s }.freeze
    end

    def replay_bid(seat, bid)
      opening = holder.nil?
      @serveret = holder unless opening
      @melding = bid
      @holder = seat
      opening ? next_challenger_after(seat) : @to_act = @serveret
    end

    # The serveret holder takes over the challenger's melding; the
    # challenger is to act again (A2).
    def replay_det_kan_jeg_selv(seat)
      @holder = seat
      @serveret = nil
      @to_act = @challenger
    end

    def replay_pas(seat)
      @passed << seat
      return replay_opening_pas(seat) if holder.nil?

      @serveret = nil
      next_challenger_after(@challenger)
    end

    def replay_opening_pas(seat)
      return @outcome = Outcome.redeal(:all_passed, forhand) if @passed.size == SEAT_COUNT

      @to_act = next_active_after(seat)
    end

    # The seat to act leaves the bidding and plays the sol melding too. If
    # it was the serveret holder, the challenger keeps the melding (A5).
    def replay_gaa_med(seat)
      @went_with << [ seat, melding ]
      @serveret = nil
      next_challenger_after(@challenger)
    end

    def next_challenger_after(seat)
      @challenger = next_active_after(seat)
      @to_act = @challenger
      @outcome = Outcome.melder(holder, melding, went_with) if @challenger.nil?
    end

    def next_active_after(seat)
      (1...SEAT_COUNT).map { |offset| (seat + offset) % SEAT_COUNT }.find { |other| other != holder && active?(other) }
    end

    def active?(seat) = !@passed.include?(seat) && @went_with.none? { |other, _melding| other == seat }

    def action_name(intent)
      case intent
      when Bid then :bid
      when Pas then :pas
      when DetKanJegSelv then :det_kan_jeg_selv
      when GaaMed then :gaa_med
      when ClaimJernhaand then :jernhaand
      end
    end
  end
end
