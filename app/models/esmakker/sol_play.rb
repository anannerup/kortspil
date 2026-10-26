module Esmakker
  # The play of a runde won on a sol-melding (REGLER §2.0 "Sol, ren sol og
  # bordlægger", §2.10): no trump, no called ace, no makker. The melder and
  # everyone who went with (#players) each play the same melding for
  # themselves; the others are modspillere. Immutable: #apply returns a
  # Result holding the next SolPlay. Stored as its actions, [[seat,
  # intent], ...], and rebuilt by replaying them, like Play.
  #
  # The phases:
  #
  # - :exchanging: bytning med katten (§2.0 "Bytning med katten"). In
  #   #exchange_order — the melder, then those who went with in the order
  #   they did, then the rest clockwise from the melder — each seat in turn
  #   takes up what is left of the kitty and lays as many cards away
  #   (Discard), any of them, the kitty's own included. What she lays away
  #   from her own hand is out of the runde and nobody sees it; kitty cards
  #   she lays back stay in the kitty for the next seat (§2.5: "Bytter
  #   spilføreren ikke alle tre, får spilleren efter … lov at bytte de
  #   resterende"). So the melder may take all three, some or none (lay
  #   the three back: keep her hand). The exchange ends when the kitty is
  #   empty or every seat has had its turn; cards still in it are out of
  #   the runde.
  # - :playing: the forhånd leads the first stik (§2.0); the winner of a
  #   stik leads the next. Follow suit (LegalMoves). No trump; the ace is
  #   the lowest card (#rank); a led joker wins the stik and leaves no suit
  #   to follow, one not led is worth nothing (§2.13; Anders, 26 October
  #   2026). A sol player who takes more stik than the
  #   melding allows (#most_stik: sol one, ren sol none) is væltet. The
  #   runde is played to the end, but stops as soon as every sol player is
  #   væltet.
  # - :complete: #result settles each sol player against the modspillere
  #   (SolResult, Scoring.sol_points).
  #
  # Bordlægger and ren bordlægger (ticket 10) are played the same way, as
  # sol and ren sol, except that the melder's cards lie open for everyone
  # once the first stik is taken (§2.0 "lægges kortene åbent efter første
  # stik"; #open_hand). Only the melder's: those who went with keep theirs
  # hidden (REGLER says "Melderens kort", §2.10).
  class SolPlay
    STIK_COUNT = Deal::HAND_SIZE
    # The most stik a sol player may take (§2.10).
    MOST_STIK = { sol: 1, ren_sol: 0, bordlaegger: 1, ren_bordlaegger: 0 }.freeze
    # The sol-meldinger played here: all four.
    PLAYED = %i[sol ren_sol bordlaegger ren_bordlaegger].freeze
    # The sol-meldinger whose melder lays her cards open after stik 1.
    OPEN_HAND = %i[bordlaegger ren_bordlaegger].freeze

    attr_reader :rules, :deal, :melder, :melding, :went_with, :forhand, :actions, :kitty, :tricks, :trick, :tricks_won, :phase

    # Whether the melding is played here.
    def self.plays?(melding) = melding.sol_melding? && PLAYED.include?(melding.kind)

    # A card's height at a sol-melding: the ace is the lowest (§2.0).
    def self.rank(card) = card.ace? ? -1 : card.rank_value

    # How a hand is sorted at a sol-melding: as always, but the ace first
    # in its suit, as the lowest card.
    def self.display_key(card) = card.joker? ? card.display_key : [ Card::DISPLAY_SUITS.index(card.suit), rank(card) ]

    # went_with: the seats that went with, in the order they did
    # (Bidding::Outcome). actions: [[seat, intent], ...] to replay. Raises
    # ArgumentError when one of them is not legal at its point.
    def initialize(rules:, deal:, melder:, melding:, forhand:, went_with: [], actions: [])
      raise ArgumentError, "only a sol-melding is played here: #{melding}" unless self.class.plays?(melding)

      @rules = rules
      @deal = deal
      @melder = melder
      @melding = melding
      @went_with = went_with.dup.freeze
      @forhand = forhand
      @actions = actions.map { |seat, intent| [ seat, intent ].freeze }.freeze
      start_state
      @actions.each { |seat, intent| replay(seat, intent) }
      [ @hands, @laid_away, @tricks, @tricks_won ].each(&:freeze)
      freeze
    end

    def apply(seat, intent)
      reason = rejection(seat, intent)
      return Result.rejected(reason) if reason

      Result.accepted(SolPlay.new(rules:, deal:, melder:, melding:, forhand:, went_with:, actions: [ *actions, [ seat, intent ] ]))
    end

    def complete? = phase == :complete

    # Who plays the sol-melding: the melder, then those who went with.
    def players = [ melder, *went_with ]

    # Those who neither won the melding nor went with.
    def modspillere = Seats::ALL - players

    def most_stik = MOST_STIK.fetch(melding.kind)

    # The sol players who took more stik than the melding allows, in the
    # order of #players.
    def vaeltet = players.select { |seat| tricks_won[seat] > most_stik }

    # The melder's cards laid open for everyone (bordlægger, ren
    # bordlægger), as she holds them now: from the end of the first stik on,
    # each card leaving it as she plays it. Nil before that, and at sol and
    # ren sol.
    def open_hand
      return nil unless OPEN_HAND.include?(melding.kind) && tricks.any?

      { seat: melder, cards: display(@hands.fetch(melder)) }
    end

    # Who exchanges with the kitty, in turn (§2.0 "Bytning med katten").
    def exchange_order
      clockwise = (1...SEAT_COUNT).map { |offset| (melder + offset) % SEAT_COUNT }
      [ *players, *(clockwise - players) ]
    end

    # The seat to act: the one exchanging, then the stik's next seat.
    def to_act
      case phase
      when :exchanging then exchange_order.fetch(@turn)
      when :playing then trick.to_act
      end
    end

    # The kitty is never on the table once the exchange starts: the seat
    # exchanging holds what is left of it (Round#view_for).
    def kitty_taken? = true

    # The seat's cards now; the seat exchanging also holds the kitty.
    def hand(seat) = seat == to_act && phase == :exchanging ? @hands.fetch(seat) + kitty : @hands.fetch(seat)

    # Every intent the seat may make now: the cards it may play (a Discard
    # of as many cards as the kitty holds is not listed).
    def legal_intents(seat) = legal_moves(seat).map { |card| PlayCard.new(card:) }

    def legal_moves(seat) = seat == to_act && phase == :playing ? LegalMoves.for(hand: hand(seat), trick:) : []

    # How many cards the seat exchanging lays away: as many as it took up.
    def discard_size = phase == :exchanging ? kitty.size : 0

    # What a seat that has to act without choosing does (a bot standing in
    # for a player who forlod): lays the kitty back, then the first legal
    # card.
    def default_intent(seat)
      return nil unless seat == to_act
      return Discard.new(cards: kitty) if phase == :exchanging

      legal_intents(seat).first
    end

    # The runde's ending (SolResult) once it is complete.
    def result
      return nil unless complete?

      SolResult.settled(melder:, melding:, players:, vaeltet:, tricks_won:, most_stik:, values: rules.points)
    end

    # What the seat may know: who plays the sol-melding, how many stik it
    # allows and who is væltet (all public), the exchange order and whose
    # turn it is, the stik on the table, the last one and who took it, the
    # stik per seat, the cards it may play now. Only the seat exchanging
    # sees the kitty, and each seat only what it laid away itself. At
    # bordlægger every seat sees the melder's open hand after stik 1. The
    # stik melding's fields are there, empty, so the client reads both
    # plays alike.
    def view_for(seat)
      {
        kind: :sol,
        trump: nil,
        called_ace: nil,
        esmakker: nil,
        selvmakker: false,
        side_stik: nil,
        fordaekt: nil,
        turned: [],
        vip_card: nil,
        bank_window: false,
        banks: [],
        players:,
        most_stik:,
        vaeltet:,
        exchange_order:,
        exchanging: phase == :exchanging ? to_act : nil,
        discard_size:,
        kitty_cards: seat == to_act && phase == :exchanging ? display(kitty) : [],
        discarded: display(@laid_away.fetch(seat)),
        current_trick: trick.to_h,
        last_trick: tricks.last&.to_h || [],
        last_trick_winner: tricks.last && winner(tricks.last),
        tricks_won:,
        open_hand:,
        legal_moves: legal_moves(seat).map(&:to_s)
      }
    end

    def ==(other)
      other.is_a?(SolPlay) && state == other.state
    end
    alias eql? ==

    def hash = state.hash

    protected

    def state = [ rules, deal, melder, melding, went_with, forhand, actions ]

    private

    def display(cards) = cards.sort_by { |card| self.class.display_key(card) }.map(&:to_s)

    def start_state
      @phase = :exchanging
      @turn = 0
      @kitty = deal.kitty.dup
      @hands = Seats::ALL.map { |seat| deal.hand(seat).dup }
      @laid_away = Seats::ALL.map { [] }
      @tricks = []
      @trick = Trick.lead(forhand)
      @tricks_won = [ 0 ] * SEAT_COUNT
    end

    def rejection(seat, intent)
      return :round_complete if complete?
      return :unknown_intent unless Play::INTENTS.any? { |kind| intent.is_a?(kind) }
      return :not_your_turn unless seat == to_act

      case intent
      when Discard then discard_rejection(seat, intent)
      when PlayCard then play_rejection(seat, intent)
      else :not_now
      end
    end

    def discard_rejection(seat, intent)
      return :not_now unless phase == :exchanging

      cards = intent.cards
      return :wrong_card_count unless cards.is_a?(Array) && cards.size == kitty.size
      return :card_not_in_hand unless cards.all? { |card| hand(seat).include?(card) }

      :duplicate_cards unless cards.uniq.size == cards.size
    end

    def play_rejection(seat, intent)
      return :not_now unless phase == :playing
      return :card_not_in_hand unless hand(seat).include?(intent.card)

      :must_follow_suit unless legal_moves(seat).include?(intent.card)
    end

    def replay(seat, intent)
      reason = rejection(seat, intent)
      raise ArgumentError, "illegal action by seat #{seat}: #{intent.inspect} (#{reason})" if reason

      intent.is_a?(Discard) ? replay_exchange(seat, intent.cards) : replay_play(seat, intent.card)
    end

    # The seat keeps the kitty cards it did not lay back; its own cards
    # laid away leave the runde; the kitty cards laid back stay for the
    # next seat.
    def replay_exchange(seat, cards)
      own = cards - kitty
      @hands[seat] = @hands[seat] + (kitty - cards) - own
      @laid_away[seat] = own
      @kitty = kitty & cards
      @turn += 1
      @phase = :playing if kitty.empty? || @turn == SEAT_COUNT
    end

    def replay_play(seat, card)
      @hands[seat] = @hands[seat] - [ card ]
      @trick = @trick.add(seat, card)
      return unless @trick.complete?

      taker = winner(@trick)
      @tricks << @trick
      @tricks_won[taker] += 1
      @trick = Trick.lead(taker)
      @phase = :complete if @tricks.size == STIK_COUNT || vaeltet.size == players.size
    end

    # Who takes a complete stik at a sol-melding: a led joker wins it;
    # otherwise the highest card of the led suit, the ace lowest. A joker
    # not led is worth nothing.
    def winner(trick)
      return trick.leader if trick.cards.first.joker?

      following = trick.plays.reject { |_seat, card| card.joker? || card.suit != trick.led_suit }
      following.max_by { |_seat, card| self.class.rank(card) }.first
    end
  end
end
