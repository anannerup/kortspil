module Esmakker
  # Svær, the es-makker bot that plays by readable rules
  # (docs/bots/esmakker-strategy.md §6): it judges its hand per trump
  # (Hand), bids the legal melding with the best risk-weighted value,
  # names trump, calls the ace, lays away, lays fordækt, and plays its
  # cards by the rules for melder, esmakker and modspiller, signalling and
  # reading discards by the bord's rule "Afkast" (Rules#afkast), and plays
  # and defends the sol-meldinger.
  #
  # It reads only the seat's view (Round#view_for) and the bord's rules,
  # remembers the stik it has seen (Memory), never banks, and is
  # deterministic: no randomness, every tie broken by a fixed order. Every
  # [valgt] number is in Params.
  #
  # The Python port (tools/esmakker_ai/esmakker_ai/svaer.py) is the same
  # bot, decision for decision; `bin/rails "esmakker:svaer_parity"` proves
  # it. Change one, change the other.
  #
  # #decide gives a Bot::Decision: the intent and the thought for "Vis
  # kort" (the first bot's shape: decision, reason, melding, expect).
  class Svaer
    include Cards

    def initialize(rules:, params: Params.standard)
      @rules = rules
      @p = params
    end

    def choose(view) = decide(view)&.intent

    # The intent with its thought, or nil when the seat has nothing to do
    # (not its turn; the bank window: it never banks).
    def decide(view)
      return nil unless view[:to_act] == view[:seat]

      action, thought = Svaer.decide(Knowledge.from_view(view, @rules), @p)
      action && Bot::Decision.new(intent: Svaer.intent(action), thought:)
    end

    # Out of turn, when the bord asks (Round#out_of_turn_seats): as melder
    # before a forhånd who is someone else leads, it lays fordækt by §6.4,
    # as it does on its own turn: always when it may, the lowest card of
    # its weakest side suit, never trump or a joker. Nil when it does not.
    def decide_out_of_turn(view)
      return nil if view[:to_act] == view[:seat] || view[:choices][:fordaekt].empty?

      k = Knowledge.from_view(view, @rules)
      card = CardPlay.fordaekt_card(k)
      card && Bot::Decision.new(intent: Svaer.intent([ :fordaekt, card ]), thought: Svaer.thought("lay_fordaekt", "fordaekt", nil, Declaring.expect(k, @p)))
    end

    # The engine's intent for one of Svær's actions ([kind, value]).
    def self.intent(action)
      kind, value = action
      case kind
      when :bid then Bidding::Bid.new(melding: Melding.parse(Cards.melding_code(value)))
      when :pas then Bidding::Pas.new
      when :selv then Bidding::DetKanJegSelv.new
      when :med then Bidding::GaaMed.new
      when :trump then ChooseTrump.new(trump: Trump.parse(Cards.trump_code(value)))
      when :ace then CallAce.new(suit: Card::SUITS[value])
      when :turn then TurnCard.new
      when :accept then AcceptTrump.new
      when :discard then Discard.new(cards: value.map { |card| Cards.card(card) })
      when :fordaekt then LayFordaekt.new(card: Cards.card(value))
      when :play then PlayCard.new(card: Cards.card(value))
      end
    end

    # [action, thought] for the seat to act, or [nil, nil].
    def self.decide(k, params)
      case k.phase
      when "bidding" then Meldingsrunde.bid(k, params) if k.bids.any? || k.can_pas
      when "choosing_trump" then Declaring.choose_trump(k, params) if k.trumps.any?
      when "calling_ace" then Declaring.call_ace(k, params) if k.aces.any?
      when "turning" then Declaring.turn(k, params) if k.can_turn || k.can_accept
      when "discarding", "exchanging" then Declaring.discard(k, params) if k.discard_size.positive?
      when "playing" then CardPlay.play(k, params) if k.legal.any? || k.fordaekt_options.any?
      end || [ nil, nil ]
    end

    def self.thought(decision, reason, melding = nil, expect = nil)
      { decision:, reason:, melding: melding && Cards.melding_code(melding), expect: expect || no_expect }
    end

    def self.no_expect(melding = nil)
      { melding: melding && Cards.melding_code(melding), stik: { self: nil, makker: nil }, makker: nil, points: nil }
    end
  end
end
