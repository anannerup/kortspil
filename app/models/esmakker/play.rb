module Esmakker
  # The play of a runde after the meldingsrunde, for a stik melding without
  # påhæng or with gode (REGLER §2.0): the melder's declaration, the kitty
  # and the 13 stik. Immutable: #apply returns a Result holding the next
  # Play. Stored as its actions, [[seat, intent], ...], and rebuilt by
  # replaying them, like Bidding.
  #
  # The phases, each the melder's until the stik:
  #
  # - :choosing_trump: she names trump, a suit or trumfløs (ChooseTrump).
  #   At gode clubs are trump (§2.0 "Gode"), so this step is skipped.
  # - :calling_ace: she calls an ace she does not hold (CallAce). Whoever
  #   holds it is the esmakker; nobody else learns who until the ace is
  #   played. Calling the ace takes the kitty up: if the ace lies there,
  #   she is selvmakker, by "accident" (§2.0 "Kalde es"). Assumption: a
  #   melder holding all four aces may call any of them and is selvmakker.
  # - :discarding: holding 16 cards, she lays three away that nobody sees
  #   (Discard), any three, the kitty's own included.
  # - :playing: the melder leads the first stik; the winner of a stik leads
  #   the next (LegalMoves, Trick).
  # - :complete: after 13 stik; #result says whether the melding gik hjem.
  class Play
    STIK_COUNT = Deal::HAND_SIZE
    DISCARD_SIZE = Deal::KITTY_SIZE

    attr_reader :rules, :deal, :melder, :melding, :actions, :trump, :called_ace, :hands, :discarded, :tricks, :trick,
                :tricks_won, :phase, :ace_played

    # actions: [[seat, intent], ...] to replay. Raises ArgumentError when
    # one of them is not legal at its point.
    def initialize(rules:, deal:, melder:, melding:, actions: [])
      raise ArgumentError, "only a stik melding without påhæng or with gode is played: #{melding}" unless self.class.plays?(melding)

      @rules = rules
      @deal = deal
      @melder = melder
      @melding = melding
      @actions = actions.map { |seat, intent| [ seat, intent ].freeze }.freeze
      start_state
      @actions.each { |seat, intent| replay(seat, intent) }
      [ @hands, @tricks, @tricks_won ].each(&:freeze)
      freeze
    end

    # Whether the melding is played here (the others come in later tickets).
    def self.plays?(melding) = melding.stik? && [ nil, :gode ].include?(melding.pahaeng)

    def apply(seat, intent)
      reason = rejection(seat, intent)
      return Result.rejected(reason) if reason

      Result.accepted(Play.new(rules:, deal:, melder:, melding:, actions: [ *actions, [ seat, intent ] ]))
    end

    def complete? = phase == :complete

    # The seat to act: the melder until the stik, then the stik's next seat.
    def to_act
      case phase
      when :complete then nil
      when :playing then trick.to_act
      else melder
      end
    end

    # The seat holding the called ace in the deal: the esmakker. Nil when
    # the melder is selvmakker (the ace lay in the kitty, or she held it).
    def esmakker
      return nil if called_ace.nil?

      seat = Seats::ALL.find { |other| deal.hand(other).include?(ace) }
      seat == melder ? nil : seat
    end

    def selvmakker? = !called_ace.nil? && esmakker.nil?

    # The cards from the kitty, once taken up.
    def kitty_taken? = !called_ace.nil?

    def hand(seat) = hands.fetch(seat)

    # Every intent the seat may make now.
    def legal_intents(seat)
      return [] unless seat == to_act

      case phase
      when :choosing_trump then Trump.all.map { |trump| ChooseTrump.new(trump:) }
      when :calling_ace then callable_aces.map { |suit| CallAce.new(suit:) }
      when :discarding then [] # any three of the 16 cards
      when :playing then legal_moves(seat).map { |card| PlayCard.new(card:) }
      end
    end

    def legal_moves(seat) = seat == to_act && phase == :playing ? LegalMoves.for(hand: hand(seat), trick:) : []

    # The aces the melder may call: those she does not hold before the
    # kitty, or any when she holds all four.
    def callable_aces
      free = Card::SUITS.reject { |suit| deal.hand(melder).include?(Card.new(rank: "A", suit:)) }
      free.empty? ? Card::SUITS : free
    end

    # What a seat that has to act without choosing does (a bot standing in
    # for a player who forlod): clubs, the first ace it may call, the kitty
    # laid back, the first legal card.
    def default_intent(seat)
      return Discard.new(cards: deal.kitty) if phase == :discarding && seat == to_act

      legal_intents(seat).first
    end

    # The runde's ending (RundeResult) once the 13 stik are played.
    def result
      return nil unless complete?

      RundeResult.played(melder:, melding:, trump:, called_ace:, esmakker:, selvmakker: selvmakker?, tricks_won:, values: rules.points)
    end

    # What the seat may know of the play: trump and the called ace (always,
    # once named), who the esmakker is only once it is known to the seat
    # (#esmakker_known?), the stik on the table, the last one and who took
    # it, the stik per seat (and per side once the esmakker is known), the
    # cards it may play now; the melder alone sees which cards came from
    # the kitty and, later, which she laid away.
    def view_for(seat)
      known = esmakker_known?(seat)
      {
        trump: trump&.to_s,
        called_ace:,
        esmakker: known ? esmakker : nil,
        selvmakker: known && selvmakker?,
        kitty_cards: seat == melder && phase == :discarding ? display(deal.kitty) : [],
        discarded: seat == melder && discarded ? display(discarded) : [],
        current_trick: trick.to_h,
        last_trick: tricks.last&.to_h || [],
        last_trick_winner: tricks.last&.winner(trump),
        tricks_won:,
        side_stik: known ? side_stik : nil,
        legal_moves: legal_moves(seat).map(&:to_s)
      }
    end

    # Whether the seat knows who the esmakker is: the esmakker herself, the
    # melder once she is selvmakker (she saw the kitty), and everybody once
    # the ace is played or the runde is over.
    def esmakker_known?(seat)
      return false if called_ace.nil?
      return true if ace_played || complete?

      seat == melder ? kitty_taken? && selvmakker? : seat == esmakker
    end

    def ==(other)
      other.is_a?(Play) && state == other.state
    end
    alias eql? ==

    def hash = state.hash

    protected

    def state = [ rules, deal, melder, melding, actions ]

    private

    def ace = Card.new(rank: "A", suit: called_ace)

    def side_stik
      side = [ melder, esmakker ].compact
      stik = side.sum { |seat| tricks_won[seat] }
      { melder: stik, modspillere: tricks.size - stik }
    end

    def display(cards) = cards.sort_by(&:display_key).map(&:to_s)

    def start_state
      @trump = melding.pahaeng == :gode ? Trump.clubs : nil
      @phase = @trump ? :calling_ace : :choosing_trump
      @called_ace = nil
      @hands = Seats::ALL.map { |seat| deal.hand(seat).dup }
      @discarded = nil
      @tricks = []
      @trick = Trick.lead(melder)
      @tricks_won = [ 0 ] * SEAT_COUNT
      @ace_played = false
    end

    def rejection(seat, intent)
      return :round_complete if complete?
      return :unknown_intent unless [ ChooseTrump, CallAce, Discard, PlayCard ].any? { |kind| intent.is_a?(kind) }
      return :not_your_turn unless seat == to_act

      case intent
      when ChooseTrump then trump_rejection(intent)
      when CallAce then ace_rejection(intent)
      when Discard then discard_rejection(intent)
      when PlayCard then play_rejection(seat, intent)
      end
    end

    def trump_rejection(intent)
      return :not_now unless phase == :choosing_trump

      :unknown_trump unless intent.trump.is_a?(Trump)
    end

    def ace_rejection(intent)
      return :not_now unless phase == :calling_ace
      return :unknown_ace unless Card::SUITS.include?(intent.suit)

      :own_ace unless callable_aces.include?(intent.suit)
    end

    def discard_rejection(intent)
      return :not_now unless phase == :discarding

      cards = intent.cards
      return :wrong_card_count unless cards.is_a?(Array) && cards.size == DISCARD_SIZE
      return :card_not_in_hand unless cards.all? { |card| hand(melder).include?(card) }

      :duplicate_cards unless cards.uniq.size == DISCARD_SIZE
    end

    def play_rejection(seat, intent)
      return :not_now unless phase == :playing
      return :card_not_in_hand unless hand(seat).include?(intent.card)

      :must_follow_suit unless legal_moves(seat).include?(intent.card)
    end

    def replay(seat, intent)
      reason = rejection(seat, intent)
      raise ArgumentError, "illegal action by seat #{seat}: #{intent.inspect} (#{reason})" if reason

      case intent
      when ChooseTrump
        @trump = intent.trump
        @phase = :calling_ace
      when CallAce
        @called_ace = intent.suit
        @hands[melder] = @hands[melder] + deal.kitty
        @phase = :discarding
      when Discard
        @discarded = intent.cards
        @hands[melder] = @hands[melder] - intent.cards
        @phase = :playing
      when PlayCard then replay_play(seat, intent.card)
      end
    end

    def replay_play(seat, card)
      @hands[seat] = @hands[seat] - [ card ]
      @ace_played ||= card == ace
      @trick = @trick.add(seat, card)
      return unless @trick.complete?

      winner = @trick.winner(trump)
      @tricks << @trick
      @tricks_won[winner] += 1
      @trick = Trick.lead(winner)
      @phase = :complete if @tricks.size == STIK_COUNT
    end
  end
end
