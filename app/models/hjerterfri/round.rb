module Hjerterfri
  # One runde of hjerterfri: a deal, the pass (if the runde has one) and 13
  # stik. Immutable: #apply returns a Result holding the next Round.
  #
  # Passing is simultaneous: hands stay as dealt and nobody sees incoming
  # cards until all four seats have passed. Then the holder of 2♣ (after
  # the pass) leads. A runde with pass direction :none starts in play.
  #
  # Who played each card is not stored. The holder of 2♣ leads the first
  # stik and each stik winner leads the next, so the plays alone say who
  # played what.
  class Round
    TRICK_COUNT = 13
    MOON = 26
    JACK_OF_DIAMONDS_POINTS = -10

    attr_reader :rules, :deal, :pass_direction, :passes, :plays

    # Rebuilds a round from its stored form: the deal, the passes (see
    # Passes) and the plays as space-separated card codes, and the pass
    # direction ("left"). Raises ArgumentError on corrupt data.
    def self.from_strings(rules:, deal:, plays:, passes: "", pass_direction: :none)
      new(rules:, deal: Deal.parse(deal), pass_direction:, passes: Passes.parse(passes), plays: plays.split)
    end

    def initialize(rules:, deal:, pass_direction: :none, passes: Passes.none, plays: [])
      @rules = rules
      @deal = deal
      @pass_direction = PassDirection.parse(pass_direction)
      @passes = passes
      check_passes
      @plays = plays.map { |play| play.is_a?(Card) ? play : Card.parse(play) }.freeze
      @hands = seats.map { |seat| hand_after_passing(seat) }
      @tricks = []
      @trick = Trick.led_by(@hands.index { |hand| hand.include?(Card::TWO_OF_CLUBS) })
      @plays.each { |card| replay(card) }
      @hands.each(&:freeze)
      @tricks.freeze
      freeze
    end

    def deal_string = deal.to_s
    def passes_string = passes.to_s
    def plays_string = plays.join(" ")

    def apply(seat, intent)
      return Result.rejected(:round_complete) if complete?

      case intent
      when Pass then apply_pass(seat, intent)
      when Play then apply_play(seat, intent)
      else Result.rejected(:unknown_intent)
      end
    end

    def phase
      return :complete if complete?
      return :passing if passing?

      :playing
    end

    def complete? = @tricks.size == TRICK_COUNT
    def passing? = pass_direction != :none && !passes.complete?
    def to_act = phase == :playing ? @trick.to_act : nil

    # The cards the seat received in the pass. Empty until all four seats
    # have passed, and in a runde without passing.
    def received_cards(seat)
      return [] if pass_direction == :none || !passes.complete?

      passes.of(PassDirection.giver(seat, pass_direction))
    end

    # Hearts are broken once a heart has been played in any stik, or Q♠
    # when the rules say the queen breaks hearts.
    def hearts_broken? = played_cards.any? { |card| breaks_hearts?(card) }

    def legal_moves(seat)
      return [] unless seat == to_act

      in_display_order(legal_moves_for(seat).cards)
    end

    # Runde points per seat, after the shooting-the-moon adjustment and J♦.
    # Empty until the runde is complete.
    def points
      return [] unless complete?

      shooter = moon_shooter
      scored = shooter ? seats.map { |seat| seat == shooter ? 0 : MOON } : penalty_points
      # J♦ −10 applies on top of the moon, also to a shooter who took it.
      # Inferred, not sourced: see the open question in ticket 09
      # (.scratch/v1/issues/09-rules-per-table.md).
      scored.each_with_index.map { |score, seat| seat == jack_of_diamonds_taker ? score + JACK_OF_DIAMONDS_POINTS : score }
    end

    # The seat that took all 26 penalty points (all hearts and Q♠), or nil
    # if nobody did. J♦ plays no part in this.
    def moon_shooter
      return nil unless complete?

      penalty_points.index(MOON)
    end

    # The seat that took J♦ when the J♦ −10 rule is on; otherwise nil.
    def jack_of_diamonds_taker
      return nil unless complete? && rules.jack_of_diamonds_minus_ten

      @tricks.find { |trick| trick.cards.include?(Card::JACK_OF_DIAMONDS) }.winner
    end

    # Everything the seat may know. Other seats' cards are never included,
    # nor what another seat passed; received cards only once all have passed.
    def view_for(seat)
      {
        seat:,
        phase:,
        pass_direction:,
        own_pass: in_display_order(passes.of(seat)),
        passed_seats: passes.passed_seats,
        received_cards: in_display_order(received_cards(seat)),
        hand: in_display_order(@hands.fetch(seat)),
        card_counts: (seats - [ seat ]).to_h { |other| [ other, @hands[other].size ] },
        current_trick: @trick.plays,
        last_trick: @tricks.last&.plays || [],
        last_trick_winner: @tricks.last&.winner,
        to_act:,
        legal_moves: legal_moves(seat),
        hearts_broken: hearts_broken?,
        points:,
        moon_shooter:,
        jack_of_diamonds_taker:
      }
    end

    def ==(other)
      other.is_a?(Round) && state == other.state
    end
    alias eql? ==

    def hash = state.hash

    protected

    def state = [ rules, deal, pass_direction, passes, plays ]

    private

    def seats = (0...Deal::SEAT_COUNT).to_a
    def played_cards = @tricks.flat_map(&:cards) + @trick.cards
    def in_display_order(cards) = cards.sort_by(&:display_key).map(&:to_s)
    def breaks_hearts?(card) = card.heart? || (rules.queen_breaks_hearts && card.queen_of_spades?)

    def penalty_points
      seats.map { |seat| @tricks.select { |trick| trick.winner == seat }.sum(&:points) }
    end

    # The dealt hand until all four seats have passed.
    def hand_after_passing(seat)
      received = received_cards(seat)
      return deal.hand(seat).dup if received.empty?

      deal.hand(seat) - passes.of(seat) + received
    end

    def legal_moves_for(seat)
      LegalMoves.new(hand: @hands[seat], trick: @trick, first_trick: @tricks.empty?, hearts_broken: hearts_broken?)
    end

    def apply_pass(seat, intent)
      return Result.rejected(:not_passing) unless phase == :passing
      return Result.rejected(:not_your_turn) unless seats.include?(seat)
      return Result.rejected(:already_passed) if passes.passed?(seat)

      codes = intent.cards
      return Result.rejected(:wrong_card_count) unless codes.is_a?(Array) && codes.size == Passes::SIZE
      return Result.rejected(:card_not_in_hand) unless codes.all? { |code| Card.valid?(code) }

      cards = codes.map { |code| Card.parse(code) }
      reason = pass_rejection_for(seat, cards)
      return Result.rejected(reason) if reason

      Result.accepted(Round.new(rules:, deal:, pass_direction:, passes: passes.add(seat, cards), plays:))
    end

    def apply_play(seat, intent)
      return Result.rejected(:passing_not_complete) if passing?
      return Result.rejected(:not_your_turn) unless seat == to_act
      return Result.rejected(:card_not_in_hand) unless Card.valid?(intent.card)

      card = Card.parse(intent.card)
      reason = legal_moves_for(seat).rejection_for(card)
      return Result.rejected(reason) if reason

      Result.accepted(Round.new(rules:, deal:, pass_direction:, passes:, plays: [ *plays, card ]))
    end

    # Passes are chosen from the hand as dealt.
    def pass_rejection_for(seat, cards)
      return :duplicate_cards unless cards.uniq.size == cards.size
      return :card_not_in_hand unless (cards - deal.hand(seat)).empty?

      nil
    end

    # Checks stored passes. Used only while constructing.
    def check_passes
      raise ArgumentError, "a runde without passing has no passes" if pass_direction == :none && !passes.none?

      passes.passed_seats.each do |seat|
        reason = pass_rejection_for(seat, passes.of(seat))
        raise ArgumentError, "pass by seat #{seat} is illegal: #{reason}" if reason
      end
    end

    # Advances the state by one stored play. Used only while constructing.
    def replay(card)
      raise ArgumentError, "play #{card} comes before passing is complete" if passing?
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
