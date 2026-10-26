module Esmakker
  # The play of a runde after the meldingsrunde, for a stik melding without
  # påhæng, with gode, halve or vip (REGLER §2.0): the declaration, the
  # kitty and the 13 stik. Immutable: #apply returns a Result holding the next
  # Play. Stored as its actions, [[seat, intent], ...], and rebuilt by
  # replaying them, like Bidding.
  #
  # The phases, each the melder's until the stik (halve excepted, below):
  #
  # - :choosing_trump: she names trump, a suit or trumfløs (ChooseTrump).
  #   At gode clubs are trump (§2.0 "Gode"), so this step is skipped.
  # - :calling_ace: she calls an ace she does not hold (CallAce). Whoever
  #   holds it is the esmakker; nobody else learns who until the ace is
  #   played. If the ace lies in the kitty, she is selvmakker, by
  #   "accident" (§2.0 "Kalde es"), and learns it when she takes the kitty
  #   up. Assumption: a melder holding all four aces may call any of them
  #   and is selvmakker.
  # - :discarding: holding her 13 cards, she chooses how many to exchange,
  #   none up to three (often all three), lays that many of them away that
  #   nobody sees (Discard), without seeing the kitty, and only then takes
  #   as many kitty cards up, from the top (§2.0 "Bytning med katten":
  #   "man får først katten op, når man har lagt 3 selv"; "man vælger selv,
  #   hvor mange kort man bytter"; Anders, 26 October 2026). Kitty cards she
  #   does not take are out of the runde (kortspils valg). So a kitty card,
  #   the called ace too, is never laid away. Everybody sees how many she
  #   exchanged (`exchanged`, the signal to bank at vip), nobody which.
  # - :playing: the forhånd leads the first stik, at every melding, whoever
  #   the melder is (§2.0 "Første udspil"; Anders, 26 October 2026: "det er
  #   altid forhånd der spiller ud ... det er helt afkoblet"); the winner of
  #   a stik leads the next (LegalMoves, Trick). Before the first card of
  #   the first stik ("før udspillet til første stik"), a melder with no
  #   card in the called ace's suit may play fordækt (LayFordaekt): on her
  #   turn when she is forhånd, otherwise out of turn while the forhånd has
  #   not led (it is no turn: #to_act stays the forhånd's, so nobody learns
  #   she had the option). Lay one card,
  #   a joker too (Anders, 26 October 2026), face down on the table; it
  #   counts as the ace's suit (FordaektCard) and its face stays secret
  #   from the others for good. Not when she knows she is selvmakker (an
  #   assumption: she has nobody to reach); when the called ace stays in the
  #   kitty untaken she does not know it, and may.
  #   At halve the melder never takes the kitty, so "efter byttet" means
  #   her own 13 cards.
  #   The esmakker must lay the called ace the first time its suit is led
  #   (Anders, 26 October 2026: "esmakker SKAL bekende første gang kuløren
  #   spilles"; #ace_owed, LegalMoves).
  # - :complete: after 13 stik; #result says whether the melding gik hjem.
  #
  # Halve (§2.0 "Halve") turns the declaration round: the melder first
  # calls the ace (:calling_ace, "jeg er makker til <farve>"), and the ace
  # holder gives herself away at once: every seat knows the esmakker from
  # then on. She is the #declarer: she names trump (:choosing_trump), a
  # suit, the called ace's too, but not trumfløs (Anders, 26 October
  # 2026), then exchanges with the kitty as the melder would
  # (:discarding). If the ace lies in the kitty,
  # nobody gives herself away: the melder is selvmakker, everyone knows,
  # and she is the declarer herself (same choices). The forhånd leads the
  # first stik, as at every melding (§2.0 "Første udspil").
  #
  # Vip (§2.0 "Vip") finds trump in the kitty: the melder first calls the
  # ace (:calling_ace), so trump may well be the called ace's suit. Then
  # (:turning) she turns the kitty's cards face up for everyone, one at a
  # time (TurnCard), and after each takes it as trump (AcceptTrump) or
  # turns the next; the third is trump in any case. A turned joker is
  # trumfløs. Cards she does not turn stay hidden from everyone, herself
  # included, until she takes the kitty up. The card she took (#vip_card,
  # 1–3) is the runde's doubling (Scoring). Once trump is named she lays
  # cards of her own away and takes as many from the top of the kitty, the
  # turned ones first (:discarding), as at an ordinary melding; then the bank window opens (:banking, below), and when it
  # closes the forhånd leads the first stik.
  #
  # Bank i bordet (§2.0, ticket 08), only at vip: in :banking, after the
  # melder has exchanged with the kitty (Anders, 26 October 2026: whether
  # she took cards is a signal to the others) and before the first stik,
  # the seats may bank (Bank), each bank doubling the points (Scoring).
  # Nobody is to act
  # (#to_act is nil); whoever may bank does so in the window. The first
  # bank is a seat's other than the melder's: a modspiller's, or the
  # esmakker's when the bord allows it (Rules#esmakker_banks_first). The
  # option looks the same to the three (#bank_offered?), so it does not give
  # the hidden esmakker away; when the bord forbids her, her press is
  # refused (:esmakker_banks_first_not_allowed), to her alone. After a bank
  # only the melder may bank once more; the second bank closes the window at
  # once. Otherwise the bord closes it when its time runs out
  # (CloseBankWindow, logged for the melder's seat): the engine knows no
  # time. After the first bank the bord gives the melder a whole window of
  # her own (Anders, 26 October 2026; Table#bank).
  class Play
    STIK_COUNT = Deal::HAND_SIZE
    DISCARD_SIZE = Deal::KITTY_SIZE
    # The code a view shows for the fordækt card before it is turned.
    FACE_DOWN = "fordaekt"
    INTENTS = [ ChooseTrump, CallAce, TurnCard, AcceptTrump, Bank, CloseBankWindow, Discard, LayFordaekt, PlayCard ].freeze
    # The most banks in a runde (§2.0: "højst bankes to gange pr. runde").
    MAX_BANKS = 2

    attr_reader :rules, :deal, :melder, :melding, :forhand, :actions, :trump, :called_ace, :hands, :discarded, :tricks, :trick,
                :tricks_won, :phase, :ace_played, :fordaekt, :turned, :vip_card, :banks

    # forhand: the seat that leads the first stik. actions: [[seat,
    # intent], ...] to replay. Raises ArgumentError when one of them is not
    # legal at its point.
    def initialize(rules:, deal:, melder:, melding:, forhand:, actions: [])
      raise ArgumentError, "only a stik melding without påhæng, with gode, halve or vip is played: #{melding}" unless self.class.plays?(melding)

      @rules = rules
      @deal = deal
      @melder = melder
      @melding = melding
      @forhand = forhand
      @actions = actions.map { |seat, intent| [ seat, intent ].freeze }.freeze
      start_state
      @actions.each { |seat, intent| replay(seat, intent) }
      [ @hands, @tricks, @tricks_won, @banks ].each(&:freeze)
      freeze
    end

    # Whether the melding is played here (the others come in later tickets).
    def self.plays?(melding) = melding.stik? && [ nil, :gode, :halve, :vip ].include?(melding.pahaeng)

    def halve? = melding.pahaeng == :halve
    def vip? = melding.pahaeng == :vip

    # At vip: the kitty's cards turned face up so far, in order.
    def turned_cards = deal.kitty.first(turned)

    def apply(seat, intent)
      reason = rejection(seat, intent)
      return Result.rejected(reason) if reason

      Result.accepted(Play.new(rules:, deal:, melder:, melding:, forhand:, actions: [ *actions, [ seat, intent ] ]))
    end

    def complete? = phase == :complete

    # The seat to act: the melder calls the ace, the declarer names trump
    # and lays away, then the stik's next seat. Nobody in the bank window.
    def to_act
      case phase
      when :complete, :banking then nil
      when :playing then trick.to_act
      when :calling_ace then melder
      else declarer
      end
    end

    # The seats that may act now though it is not their turn (#to_act stays
    # whose turn it is): the melder, while she may lay fordækt before a
    # forhånd who is someone else leads. For the bord, to give its bots the
    # chance a human has; no view shows it to the others.
    def out_of_turn_seats = melder != to_act && fordaekt_allowed? ? [ melder ] : []

    # Who names trump and takes the kitty: the melder, but at halve the
    # esmakker (the melder herself when she is selvmakker).
    def declarer = halve? ? esmakker || melder : melder

    # The seat holding the called ace in the deal: the esmakker. Nil when
    # the melder is selvmakker (the ace lay in the kitty, or she held it).
    def esmakker
      return nil if called_ace.nil?

      seat = Seats::ALL.find { |other| deal.hand(other).include?(ace) }
      seat == melder ? nil : seat
    end

    def selvmakker? = !called_ace.nil? && esmakker.nil?

    # Whether the declarer has taken the kitty up: after her discard.
    def kitty_taken? = @kitty_taken

    # How many cards lie in the kitty on the table: three until the
    # declarer has exchanged; none after (cards she did not take are out of
    # the runde) (Round#view_for).
    def kitty_count = kitty_taken? ? 0 : deal.kitty.size

    def hand(seat) = hands.fetch(seat)

    def banking? = phase == :banking

    # Whether the seat is offered "Bank" now: before the first bank every
    # seat but the melder's (the esmakker's too, whatever the bord says, so
    # the option does not give her away); after it the melder alone.
    def bank_offered?(seat)
      return false unless banking?

      banks.empty? ? seat != melder : seat == melder
    end

    # Every intent the seat may make now: out of turn, the melder's
    # fordækt cards while the forhånd has not led (#fordaekt_intents).
    def legal_intents(seat)
      return bank_offered?(seat) ? [ Bank.new ] : [] if banking?
      return fordaekt_intents(seat) unless seat == to_act

      case phase
      when :choosing_trump then trumps.map { |trump| ChooseTrump.new(trump:) }
      when :calling_ace then callable_aces.map { |suit| CallAce.new(suit:) }
      when :turning then turn_intents
      when :discarding then [] # none up to three of her 13 cards
      when :playing then playing_intents(seat)
      end
    end

    # The cards the seat may play now: Cards and Jokers from its hand, and
    # the melder's FordaektCard while it waits on the table.
    def legal_moves(seat)
      return [] unless seat == to_act && phase == :playing

      LegalMoves.for(hand: playable(seat), trick:, ace: ace_owed(seat))
    end

    # The called ace when the seat is the esmakker, holds it and its suit
    # has not been led in a stik before this one (the fordækt card led
    # counts as the suit): then she must lay it when the suit is led, and
    # may lead the suit only with it (LegalMoves). Nil otherwise: for
    # everybody else, the selvmakker, and once the suit has been led.
    def ace_owed(seat)
      return nil if called_ace.nil? || seat != esmakker || !hand(seat).include?(ace)

      ace if tricks.none? { |stik| stik.led_suit == called_ace }
    end

    # Whether the melder may lay a card fordækt now: before the first card
    # of the first stik (whoever is to lead it), unless she knows she is
    # selvmakker, holding no card of the ace's suit.
    def fordaekt_allowed?
      phase == :playing && tricks.empty? && trick.empty? && fordaekt.nil? && !(selvmakker? && esmakker_known?(melder)) &&
        hand(melder).none? { |card| !card.joker? && card.suit == called_ace }
    end

    # The fordækt card lies face down on the table, not played yet.
    def fordaekt_waiting? = !fordaekt.nil? && [ *tricks.flat_map(&:cards), *trick.cards ].none?(fordaekt)

    # The trumps the declarer may name: any suit or trumfløs, but at halve
    # a suit (the called ace's too; Anders, 26 October 2026).
    def trumps = halve? ? Trump.all.reject(&:trumfloes?) : Trump.all

    # The aces the melder may call: those she does not hold before the
    # kitty, or any when she holds all four.
    def callable_aces
      free = Card::SUITS.reject { |suit| deal.hand(melder).include?(Card.new(rank: "A", suit:)) }
      free.empty? ? Card::SUITS : free
    end

    # The runde's plain default for a seat to act (the engine tests play
    # runder out with it; bots choose with Esmakker::Bot): clubs, the first
    # ace it may call, at vip the first kitty card turned as trump, the
    # first three cards of her hand laid away, the first legal card.
    # Never a bank.
    def default_intent(seat)
      return nil if banking?
      return Discard.new(cards: hand(seat).first(DISCARD_SIZE)) if phase == :discarding && seat == to_act

      legal_intents(seat).first # a card, never fordækt
    end

    # The runde's ending (RundeResult) once the 13 stik are played.
    def result
      return nil unless complete?

      RundeResult.played(melder:, melding:, trump:, called_ace:, esmakker:, selvmakker: selvmakker?, tricks_won:, values: rules.points, vip_card:, banks: banks.size)
    end

    # What the seat may know of the play: trump and the called ace (always,
    # once named), who the esmakker is only once it is known to the seat
    # (#esmakker_known?), the stik on the table, the last one and who took
    # it, the stik per seat (and per side once the esmakker is known), the
    # cards it may play now; the declarer alone sees which cards she laid
    # away and, once she has taken the kitty up (after the discard, never
    # before), which cards came from it (`kitty_cards`, until the first
    # stik is taken, so her hand can mark them); everybody sees how many
    # she exchanged (`exchanged`, nil before). At vip everyone sees the
    # kitty cards turned so far (`turned`), never the others, and which
    # one became trump (`vip_card`), whether the bank window is open
    # (`bank_window`) and who banked, in order (`banks`). The fordækt card
    # (#fordaekt_view) is face down for everyone but the melder, on the table
    # and in the stik, for the whole runde and after: it is never turned.
    # Every stik played so far (`tricks`: who led, the cards as the seat saw
    # them, who took it) is what a player at the bord has seen and may
    # remember; the bots read it (Esmakker::Svaer).
    def view_for(seat)
      known = esmakker_known?(seat)
      {
        trump: trump&.to_s,
        called_ace:,
        esmakker: known ? esmakker : nil,
        selvmakker: known && selvmakker?,
        turned: turned_cards.map(&:to_s),
        vip_card:,
        bank_window: banking?,
        banks:,
        discard_size: phase == :discarding ? DISCARD_SIZE : 0,
        kitty_cards: seat == declarer && kitty_taken? && tricks.empty? ? display(taken) : [],
        exchanged: kitty_taken? ? taken.size : nil,
        discarded: seat == declarer && discarded ? display(discarded) : [],
        current_trick: stik_view(trick, seat),
        last_trick: tricks.last ? stik_view(tricks.last, seat) : [],
        last_trick_winner: tricks.last && trick_winner(tricks.last),
        tricks: tricks.map { |stik| { leader: stik.leader, plays: stik_view(stik, seat), winner: trick_winner(stik) } },
        fordaekt: fordaekt_view(seat),
        tricks_won:,
        side_stik: known ? side_stik : nil,
        legal_moves: legal_moves(seat).map(&:to_s)
      }
    end

    # Whether the seat knows who the esmakker is: the esmakker herself, the
    # melder once she is selvmakker (she called her own ace, or took the
    # ace up with the kitty after her discard), and everybody once
    # the ace is played or the runde is over. At halve everybody knows as
    # soon as the ace is called: its holder gives herself away, or nobody
    # does and the melder is selvmakker. At vip everybody knows she is
    # selvmakker once the called ace is turned face up from the kitty.
    def esmakker_known?(seat)
      return false if called_ace.nil?
      return true if halve? || ace_played || complete? || turned_cards.include?(ace)

      seat == melder ? selvmakker? && (deal.hand(melder) + taken).include?(ace) : seat == esmakker
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

    # The kitty cards the declarer took up (none before she exchanged).
    def taken = @taken

    def trick_winner(stik) = stik.winner(trump, joker_trumpable: rules.joker_trumpable)

    def playable(seat) = seat == melder && fordaekt_waiting? ? [ *hand(seat), fordaekt ] : hand(seat)

    # The card the seat holds for the played `card` (the fordækt card is
    # played by its real card), nil when it holds none.
    def held(seat, card) = playable(seat).find { |own| own == card || (own.fordaekt? && own.card == card) }

    # The cards to play as PlayCard intents (the fordækt card by its real
    # card), then the cards the melder may lay fordækt (any, jokers too).
    def playing_intents(seat)
      plays = legal_moves(seat).map { |card| PlayCard.new(card: card.fordaekt? ? card.card : card) }
      plays + fordaekt_intents(seat)
    end

    # The cards the melder may lay fordækt now (any, jokers too), in turn
    # or not; none for any other seat.
    def fordaekt_intents(seat) = seat == melder && fordaekt_allowed? ? hand(seat).map { |card| LayFordaekt.new(card:) } : []

    # A stik as the seat may see it: the fordækt card face down
    # (FACE_DOWN) to everyone but the melder.
    def stik_view(stik, seat) = stik.to_h.map { |play| play[:fordaekt] && seat != melder ? play.merge(card: FACE_DOWN) : play }

    # The fordækt card as the seat may see it, nil when none was laid: its
    # face (the melder's alone, never anyone else's) and whether it still
    # lies on the table.
    def fordaekt_view(seat)
      return nil if fordaekt.nil?

      { seat: melder, card: seat == melder ? fordaekt.to_s : nil, waiting: fordaekt_waiting? }
    end

    def side_stik
      side = [ melder, esmakker ].compact
      stik = side.sum { |seat| tricks_won[seat] }
      { melder: stik, modspillere: tricks.size - stik }
    end

    def display(cards) = cards.sort_by(&:display_key).map(&:to_s)

    # At vip: "det er trumf" once a card is turned, and the next card while
    # one is left (the third is trump without asking).
    def turn_intents = [ (AcceptTrump.new if turned.positive?), TurnCard.new ].compact

    def start_state
      @trump = melding.pahaeng == :gode ? Trump.clubs : nil
      @phase = @trump || halve? || vip? ? :calling_ace : :choosing_trump
      @turned = 0
      @vip_card = nil
      @banks = []
      @called_ace = nil
      @kitty_taken = false
      @hands = Seats::ALL.map { |seat| deal.hand(seat).dup }
      @discarded = nil
      @taken = []
      @tricks = []
      @trick = Trick.lead(forhand)
      @tricks_won = [ 0 ] * SEAT_COUNT
      @ace_played = false
      @fordaekt = nil
    end

    def rejection(seat, intent)
      return :round_complete if complete?
      return :unknown_intent unless INTENTS.any? { |kind| intent.is_a?(kind) }
      return bank_rejection(seat) if intent.is_a?(Bank)
      return close_rejection(seat) if intent.is_a?(CloseBankWindow)
      return fordaekt_rejection(seat, intent) if intent.is_a?(LayFordaekt)
      return :not_your_turn unless seat == to_act

      case intent
      when ChooseTrump then trump_rejection(intent)
      when CallAce then ace_rejection(intent)
      when TurnCard then :not_now unless phase == :turning
      when AcceptTrump then accept_rejection
      when Discard then discard_rejection(intent)
      when PlayCard then play_rejection(seat, intent)
      end
    end

    # Who may bank (§2.0): not the melder first; the esmakker first only
    # when the bord allows it; after a bank only the melder.
    def bank_rejection(seat)
      return :not_now unless banking?
      return :only_melder_banks_again unless banks.empty? || seat == melder
      return :melder_banks_second if banks.empty? && seat == melder

      :esmakker_banks_first_not_allowed if banks.empty? && seat == esmakker && !rules.esmakker_banks_first
    end

    def close_rejection(seat)
      return :not_now unless banking?

      :not_your_turn unless seat == melder
    end

    def fordaekt_rejection(seat, intent)
      return :not_your_turn unless seat == melder
      return :not_now unless phase == :playing && tricks.empty? && trick.empty? && fordaekt.nil?
      return :card_not_in_hand unless hand(melder).include?(intent.card)
      :fordaekt_not_allowed unless fordaekt_allowed?
    end

    def trump_rejection(intent)
      return :not_now unless phase == :choosing_trump
      return :unknown_trump unless intent.trump.is_a?(Trump)

      :no_trumfloes_at_halve unless trumps.include?(intent.trump)
    end

    def ace_rejection(intent)
      return :not_now unless phase == :calling_ace
      return :unknown_ace unless Card::SUITS.include?(intent.suit)

      :own_ace unless callable_aces.include?(intent.suit)
    end

    def accept_rejection
      return :not_now unless phase == :turning

      :nothing_turned if turned.zero?
    end

    def discard_rejection(intent)
      return :not_now unless phase == :discarding

      cards = intent.cards
      return :wrong_card_count unless cards.is_a?(Array) && cards.size <= DISCARD_SIZE
      return :card_not_in_hand unless cards.all? { |card| hand(declarer).include?(card) }

      :duplicate_cards unless cards.uniq.size == cards.size
    end

    def play_rejection(seat, intent)
      return :not_now unless phase == :playing

      card = held(seat, intent.card)
      return :card_not_in_hand unless card

      LegalMoves.rejection(card:, hand: playable(seat), trick:, ace: ace_owed(seat))
    end

    def replay(seat, intent)
      reason = rejection(seat, intent)
      return lay_away_legacy(intent.cards) if reason == :card_not_in_hand && legacy_discard?(intent)
      reason = legacy_lead(seat, intent) if reason == :not_your_turn
      reason = nil if legacy_ace_play?(reason)
      raise ArgumentError, "illegal action by seat #{seat}: #{intent.inspect} (#{reason})" if reason

      case intent
      when ChooseTrump
        @trump = intent.trump
        @phase = halve? ? :discarding : :calling_ace
      when CallAce
        @called_ace = intent.suit
        @phase = if halve? then :choosing_trump elsif vip? then :turning else :discarding end
      when TurnCard
        @turned += 1
        name_vip_trump if turned == Deal::KITTY_SIZE
      when AcceptTrump then name_vip_trump
      when Bank
        @banks << seat
        @phase = :playing if banks.size == MAX_BANKS
      when CloseBankWindow then @phase = :playing
      when Discard then lay_away(intent.cards)
      when LayFordaekt
        @fordaekt = FordaektCard.new(card: intent.card, suit: called_ace)
        @hands[melder] = @hands[melder] - [ intent.card ]
      when PlayCard then replay_play(seat, held(seat, intent.card))
      end
    end

    # At vip the card turned last is trump: its suit, or trumfløs for a
    # joker. The melder exchanges with the kitty; then the bank window
    # opens.
    def name_vip_trump
      card = turned_cards.last
      @vip_card = turned
      @trump = card.joker? ? Trump.trumfloes : Trump.new(suit: card.suit)
      @phase = :discarding
    end

    # The declarer lays the cards away, then takes as many cards up from
    # the top of the kitty.
    def lay_away(cards)
      @discarded = cards
      @taken = deal.kitty.first(cards.size)
      @hands[declarer] = @hands[declarer] - cards + taken
      exchanged!
    end

    def exchanged!
      @kitty_taken = true
      @phase = vip? ? :banking : :playing
    end

    # A first lead stored before 26 October 2026, when the melder led the
    # first stik at a stik melding (now the forhånd does): the melder's
    # card before any other in the runde. Only replayed from a stored log
    # (never accepted by #apply): the stik is then hers to lead. Returns
    # the card's rejection then, :not_your_turn otherwise.
    def legacy_lead(seat, intent)
      return :not_your_turn unless intent.is_a?(PlayCard) && seat == melder && phase == :playing && tricks.empty? && trick.empty?

      @trick = Trick.lead(melder)
      play_rejection(seat, intent)
    end

    # A discard stored before 26 October 2026, when the declarer took the
    # kitty up first and laid any three of her 16 cards away: one holding
    # a kitty card. Only replayed from a stored log (never accepted by
    # #apply). She kept the kitty cards she did not lay back.
    def lay_away_legacy(cards)
      @discarded = cards
      @taken = deal.kitty - cards
      @hands[declarer] = @hands[declarer] + deal.kitty - cards
      exchanged!
    end

    def legacy_discard?(intent)
      intent.is_a?(Discard) && phase == :discarding && intent.cards.uniq.size == DISCARD_SIZE &&
        intent.cards.all? { |card| hand(declarer).include?(card) || deal.kitty.include?(card) }
    end

    # A play the esmakker could make before 26 October 2026, when the
    # called ace was not owed (#ace_owed): another card of its suit when it
    # was led the first time, or a lead in it without the ace. Only replayed
    # from a stored log, recognised by that play itself (never accepted by
    # #apply); the play goes on by the rules from there, the suit now led.
    def legacy_ace_play?(reason) = reason == :must_play_called_ace

    def replay_play(seat, card)
      @hands[seat] = @hands[seat] - [ card ]
      @ace_played ||= card == ace
      @trick = @trick.add(seat, card)
      return unless @trick.complete?

      winner = trick_winner(@trick)
      @tricks << @trick
      @tricks_won[winner] += 1
      @trick = Trick.lead(winner)
      @phase = :complete if @tricks.size == STIK_COUNT
    end
  end
end
