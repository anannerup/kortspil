module Esmakker
  # One stik: the seat that led and the cards played, in order, as
  # [seat, card] pairs. Immutable; #add returns the next Trick. A card is a
  # Card, a Joker or the melder's FordaektCard (counting as the called
  # ace's suit).
  #
  # Who wins (REGLER §2.0, §2.13), #winner:
  # - a led joker wins the stik; with the bord's setting "jokere kan
  #   stikkes med trumf" (Rules#joker_trumpable, standard no) the highest
  #   trump in the stik beats it;
  # - otherwise the highest trump wins, or, with no trump in it (or
  #   trumfløs), the highest card of the led suit. The called ace is a card
  #   like any other: trump beats it (Anders, 26 October 2026);
  # - a joker that was not led is worth nothing.
  # A stik led with a joker has no suit to follow (#led_suit is nil): every
  # card is legal in it (Anders, 26 October 2026).
  class Trick < Data.define(:leader, :plays)
    SIZE = SEAT_COUNT

    def self.lead(leader) = new(leader:, plays: [])

    def initialize(leader:, plays:)
      super(leader:, plays: plays.map { |seat, card| [ seat, card ].freeze }.freeze)
    end

    def add(seat, card) = with(plays: [ *plays, [ seat, card ] ])

    def empty? = plays.empty?
    def complete? = plays.size == SIZE
    def cards = plays.map(&:last)

    # The seat to play next, nil once complete.
    def to_act = complete? ? nil : (leader + plays.size) % SEAT_COUNT

    # The suit to follow: the led card's, nil while none is down or when a
    # joker was led (then nobody has to follow anything).
    def led_suit
      lead = cards.first
      lead.nil? || lead.joker? ? nil : lead.suit
    end

    # The seat that takes the stik, by `trump` (a Trump) and the bord's
    # joker setting. Only for a complete stik.
    def winner(trump, joker_trumpable: false)
      trumps = trump.trumfloes? ? [] : plays.select { |_seat, card| !card.joker? && card.suit == trump.suit }
      return leader if cards.first.joker? && (trumps.empty? || !joker_trumpable)

      pool = trumps.any? ? trumps : plays.select { |_seat, card| !card.joker? && card.suit == led_suit }
      pool.max_by { |_seat, card| card.rank_value }.first
    end

    # Each play as { seat:, card: }; the fordækt card is marked
    # (fordaekt: true), so a view can hide its face.
    def to_h = plays.map { |seat, card| card.fordaekt? ? { seat:, card: card.to_s, fordaekt: true } : { seat:, card: card.to_s } }
  end
end
