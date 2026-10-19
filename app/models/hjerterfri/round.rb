module Hjerterfri
  # One runde of hjerterfri: a deal played out over 13 stik. Immutable:
  # #apply returns a Result holding the next Round.
  #
  # Who played each card is not stored. The holder of 2♣ leads the first
  # stik and each stik winner leads the next, so the plays alone say who
  # played what.
  class Round
    TRICK_COUNT = 13
    MOON = 26

    attr_reader :rules, :deal, :plays

    # Rebuilds a round from its stored form: the deal and the plays as
    # space-separated card codes. Raises ArgumentError on corrupt data.
    def self.from_strings(rules:, deal:, plays:)
      new(rules:, deal: Deal.parse(deal), plays: plays.split)
    end

    def initialize(rules:, deal:, plays: [])
      @rules = rules
      @deal = deal
      @plays = plays.map { |play| play.is_a?(Card) ? play : Card.parse(play) }.freeze
      @hands = deal.hands.map(&:dup)
      @tricks = []
      @trick = Trick.led_by(deal.holder_of(Card::TWO_OF_CLUBS))
      @plays.each { |card| replay(card) }
      @hands.each(&:freeze)
      @tricks.freeze
      freeze
    end

    def deal_string = deal.to_s
    def plays_string = plays.join(" ")

    def apply(seat, intent)
      return Result.rejected(:round_complete) if complete?
      return Result.rejected(:unknown_intent) unless intent.is_a?(Play)
      return Result.rejected(:not_your_turn) unless seat == to_act
      return Result.rejected(:card_not_in_hand) unless Card.valid?(intent.card)

      card = Card.parse(intent.card)
      reason = legal_moves_for(seat).rejection_for(card)
      return Result.rejected(reason) if reason

      Result.accepted(Round.new(rules:, deal:, plays: [ *plays, card ]))
    end

    def phase = complete? ? :complete : :playing
    def complete? = @tricks.size == TRICK_COUNT
    def to_act = complete? ? nil : @trick.to_act

    # Hearts are broken once a heart has been played in any stik.
    def hearts_broken? = played_cards.any?(&:heart?)

    def legal_moves(seat)
      return [] unless seat == to_act

      in_display_order(legal_moves_for(seat).cards)
    end

    # Runde points per seat, after the shooting-the-moon adjustment.
    # Empty until the runde is complete.
    def points
      return [] unless complete?

      shooter = moon_shooter
      return points_taken unless shooter

      seats.map { |seat| seat == shooter ? 0 : MOON }
    end

    # The seat that took all 26 points, or nil if nobody did.
    def moon_shooter
      return nil unless complete?

      points_taken.index(MOON)
    end

    # Everything the seat may know. Other seats' cards are never included.
    def view_for(seat)
      {
        seat:,
        phase:,
        hand: in_display_order(@hands.fetch(seat)),
        card_counts: (seats - [ seat ]).to_h { |other| [ other, @hands[other].size ] },
        current_trick: @trick.plays,
        last_trick: @tricks.last&.plays || [],
        last_trick_winner: @tricks.last&.winner,
        to_act:,
        legal_moves: legal_moves(seat),
        hearts_broken: hearts_broken?,
        points:,
        moon_shooter:
      }
    end

    def ==(other)
      other.is_a?(Round) && rules == other.rules && deal == other.deal && plays == other.plays
    end
    alias eql? ==

    def hash = [ rules, deal, plays ].hash

    private

    def seats = (0...Deal::SEAT_COUNT).to_a
    def played_cards = @tricks.flat_map(&:cards) + @trick.cards
    def in_display_order(cards) = cards.sort_by(&:display_key).map(&:to_s)

    def points_taken
      seats.map { |seat| @tricks.select { |trick| trick.winner == seat }.sum(&:points) }
    end

    def legal_moves_for(seat)
      LegalMoves.new(hand: @hands[seat], trick: @trick, first_trick: @tricks.empty?, hearts_broken: hearts_broken?)
    end

    # Advances the state by one stored play. Used only while constructing.
    def replay(card)
      raise ArgumentError, "play #{card} comes after the runde is complete" if complete?

      seat = to_act
      reason = legal_moves_for(seat).rejection_for(card)
      raise ArgumentError, "play #{card} by seat #{seat} is illegal: #{reason}" if reason

      @hands[seat].delete(card)
      @trick = @trick.add(card)
      return unless @trick.complete?

      @tricks << @trick
      @trick = Trick.led_by(@trick.winner)
    end
  end
end
