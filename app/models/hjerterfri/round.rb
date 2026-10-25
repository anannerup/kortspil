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
  #
  # Under shooter's choice, a runde whose 13 stik went to a moon shooter is
  # complete only once the shooter has made their MoonChoice.
  class Round
    TRICK_COUNT = 13
    MOON = 26
    JACK_OF_DIAMONDS_POINTS = -10

    attr_reader :rules, :deal, :pass_direction, :passes, :plays, :moon_choice

    # Rebuilds a round from its stored form: the deal, the passes (see
    # Passes) and the plays as space-separated card codes, the pass
    # direction ("left") and the moon choice, if any. Raises ArgumentError
    # on corrupt data.
    def self.from_strings(rules:, deal:, plays:, passes: "", pass_direction: :none, moon_choice: nil)
      new(rules:, deal: Deal.parse(deal), pass_direction:, passes: Passes.parse(passes), plays: plays.split, moon_choice: moon_choice.presence)
    end

    def initialize(rules:, deal:, pass_direction: :none, passes: Passes.none, plays: [], moon_choice: nil)
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
      @moon_choice = moon_choice
      check_moon_choice
      @hands.each(&:freeze)
      @tricks.freeze
      freeze
    end

    def deal_string = deal.to_s
    def passes_string = passes.to_s
    def plays_string = plays.join(" ")

    # The columns the runde's row stores (Round, the ActiveRecord model).
    def stored = { passes: passes_string, plays: plays_string, moon_choice: }

    # Grows with every pass, play and moon choice (Game#version).
    def steps = passes.passed_seats.size + plays.size + (moon_choice ? 1 : 0)

    # The seats that are to act now: in the pass every seat that has not
    # passed (they pass at the same time), in play the seat whose turn it
    # is, and a moon shooter that is to choose.
    def seats_to_act = passing? ? seats.reject { |seat| passes.passed?(seat) } : [ to_act ].compact

    def apply(seat, intent)
      return Result.rejected(:round_complete) if complete?

      case intent
      when Pass then apply_pass(seat, intent)
      when Play then apply_play(seat, intent)
      when MoonChoice then apply_moon_choice(seat, intent)
      else Result.rejected(:unknown_intent)
      end
    end

    def phase
      return :complete if complete?
      return :choosing_moon if choosing_moon?
      return :passing if passing?

      :playing
    end

    def complete? = all_tricks_played? && !choosing_moon?
    def all_tricks_played? = @tricks.size == TRICK_COUNT
    def passing? = pass_direction != :none && !passes.complete?

    # All 13 stik are played, the shooter took the moon and shooter's choice
    # is on, but the shooter has not chosen yet.
    def choosing_moon? = moon_choice.nil? && rules.shooters_choice && !moon_shooter.nil?

    # The seat to play, or the moon shooter while they choose.
    def to_act
      case phase
      when :playing then @trick.to_act
      when :choosing_moon then moon_shooter
      end
    end

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
      return [] unless phase == :playing && seat == to_act

      in_display_order(legal_moves_for(seat).cards)
    end

    # Runde points per seat, after the shooting-the-moon adjustment and J♦.
    # Empty until the runde is complete.
    #
    # The moon gives 26 to everyone else, or −26 to the shooter when they
    # chose so under shooter's choice. J♦ −10 never applies to the shooter;
    # another seat that took J♦ still gets it (Anders, ticket 09).
    def points
      return [] unless complete?

      shooter = moon_shooter
      scored = shooter ? moon_points(shooter) : penalty_points
      jack = jack_of_diamonds_taker
      scored.each_with_index.map { |score, seat| seat == jack && seat != shooter ? score + JACK_OF_DIAMONDS_POINTS : score }
    end

    # Points each seat has taken so far, from the completed stik: hearts and
    # Q♠, plus J♦ −10 when that rule is on. No moon adjustment; that is only
    # known at the end (see #points). Taken stik are public, so this may be
    # shown to every seat during the runde.
    def points_taken
      seats.map do |seat|
        taken = @tricks.select { |trick| trick.winner == seat }
        jack = rules.jack_of_diamonds_minus_ten && taken.any? { |trick| trick.cards.include?(Card::JACK_OF_DIAMONDS) }
        taken.sum(&:points) + (jack ? JACK_OF_DIAMONDS_POINTS : 0)
      end
    end

    # The seat that took all 26 penalty points (all hearts and Q♠), or nil
    # if nobody did. J♦ plays no part in this. Known once all stik are played.
    def moon_shooter
      return nil unless all_tricks_played?

      penalty_points.index(MOON)
    end

    # The seat that took J♦ when the J♦ −10 rule is on; otherwise nil.
    def jack_of_diamonds_taker
      return nil unless all_tricks_played? && rules.jack_of_diamonds_minus_ten

      @tricks.find { |trick| trick.cards.include?(Card::JACK_OF_DIAMONDS) }.winner
    end

    # Everything the seat may know. Other seats' cards are never included,
    # nor what another seat passed; received cards only once all have passed.
    # Completed stik, the points taken and the rules are public: everyone
    # at the table saw them (the bots read them, ticket 21).
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
        tricks: @tricks.map { |trick| { plays: trick.plays, winner: trick.winner } },
        points_taken:,
        rules: rules.to_h,
        to_act:,
        legal_moves: legal_moves(seat),
        hearts_broken: hearts_broken?,
        points:,
        moon_shooter:,
        moon_choice:,
        jack_of_diamonds_taker:
      }
    end

    def ==(other)
      other.is_a?(Round) && state == other.state
    end
    alias eql? ==

    def hash = state.hash

    protected

    def state = [ rules, deal, pass_direction, passes, plays, moon_choice ]

    private

    def seats = (0...Deal::SEAT_COUNT).to_a
    def played_cards = @tricks.flat_map(&:cards) + @trick.cards
    def in_display_order(cards) = cards.sort_by(&:display_key).map(&:to_s)
    def breaks_hearts?(card) = card.heart? || (rules.queen_breaks_hearts && card.queen_of_spades?)

    def moon_points(shooter)
      return seats.map { |seat| seat == shooter ? -MOON : 0 } if moon_choice == "subtract_from_self"

      seats.map { |seat| seat == shooter ? 0 : MOON }
    end

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
      return Result.rejected(:choosing_moon) if choosing_moon?
      return Result.rejected(:not_your_turn) unless seat == to_act
      return Result.rejected(:card_not_in_hand) unless Card.valid?(intent.card)

      card = Card.parse(intent.card)
      reason = legal_moves_for(seat).rejection_for(card)
      return Result.rejected(reason) if reason

      Result.accepted(Round.new(rules:, deal:, pass_direction:, passes:, plays: [ *plays, card ]))
    end

    def apply_moon_choice(seat, intent)
      return Result.rejected(:not_choosing_moon) unless choosing_moon?
      return Result.rejected(:not_your_turn) unless seat == to_act
      return Result.rejected(:unknown_moon_choice) unless MoonChoice::OPTIONS.include?(intent.option)

      Result.accepted(Round.new(rules:, deal:, pass_direction:, passes:, plays:, moon_choice: intent.option))
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

    # Checks a stored moon choice. Used only while constructing.
    def check_moon_choice
      return if moon_choice.nil?
      raise ArgumentError, "unknown moon choice #{moon_choice.inspect}" unless MoonChoice::OPTIONS.include?(moon_choice)
      raise ArgumentError, "a moon choice needs shooter's choice and a moon shooter" unless rules.shooters_choice && moon_shooter
    end

    # Advances the state by one stored play. Used only while constructing.
    def replay(card)
      raise ArgumentError, "play #{card} comes before passing is complete" if passing?
      raise ArgumentError, "play #{card} comes after the runde is complete" if all_tricks_played?

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
