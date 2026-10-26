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
  # - "esset må ikke stikkes": in a stik led in the called ace's suit (the
  #   fordækt card counts as that suit), the called ace takes the stik once
  #   it falls in it, whatever trump lies there, before or after it;
  # - otherwise the highest trump wins, or, with no trump in it (or
  #   trumfløs), the highest card of the led suit;
  # - a joker that was not led is worth nothing.
  # The led suit is the suit of the first playing card, so after a led
  # joker the next playing card sets the suit to follow (C4, an assumption;
  # REGLER says nothing about it).
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

    # The suit to follow: the first playing card's, nil while none is down.
    def led_suit = cards.find { |card| !card.joker? }&.suit

    # Whether the stik was led in `suit` (a joker led is no suit; the
    # fordækt card is the called ace's suit).
    def led_in?(suit)
      lead = cards.first
      !lead.nil? && !lead.joker? && lead.suit == suit
    end

    # The seat that laid the ace of `suit` in a stik led in that suit, nil
    # when it has not fallen here: the ace "esset må ikke stikkes" protects.
    def protected_ace_seat(suit)
      return nil if suit.nil? || !led_in?(suit)

      ace = Card.new(rank: "A", suit:)
      plays.find { |_seat, card| card == ace }&.first
    end

    # The seat that takes the stik, by `trump` (a Trump), the bord's joker
    # setting and the called ace's suit when the ace is protected (nil when
    # there is no esmakker). Only for a complete stik.
    def winner(trump, joker_trumpable: false, called_ace: nil)
      trumps = trump.trumfloes? ? [] : plays.select { |_seat, card| !card.joker? && card.suit == trump.suit }
      return leader if cards.first.joker? && (trumps.empty? || !joker_trumpable)

      ace_seat = protected_ace_seat(called_ace)
      return ace_seat if ace_seat

      pool = trumps.any? ? trumps : plays.select { |_seat, card| !card.joker? && card.suit == led_suit }
      pool.max_by { |_seat, card| card.rank_value }.first
    end

    # Each play as { seat:, card: }; the fordækt card is marked
    # (fordaekt: true), so a view can hide it until the stik is taken.
    def to_h = plays.map { |seat, card| card.fordaekt? ? { seat:, card: card.to_s, fordaekt: true } : { seat:, card: card.to_s } }
  end
end
