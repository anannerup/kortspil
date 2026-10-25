module Esmakker
  # One stik: the seat that led and the cards played, in order, as
  # [seat, card] pairs. Immutable; #add returns the next Trick.
  #
  # Who wins (REGLER §2.0, §2.13), until ticket 04 adds the bord's joker
  # setting:
  # - a led joker wins the stik;
  # - otherwise the highest trump wins, or, with no trump in it (or
  #   trumfløs), the highest card of the led suit;
  # - a joker that was not led is worth nothing.
  # The led suit is the suit of the first playing card, so after a led
  # joker the next playing card sets the suit to follow (an assumption;
  # REGLER says nothing about it, see ticket 03's notes).
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

    # The seat that takes the stik, by `trump` (a Trump). Only for a
    # complete stik.
    def winner(trump)
      return leader if cards.first.joker?

      valued = plays.reject { |_seat, card| card.joker? }
      trumps = trump.trumfloes? ? [] : valued.select { |_seat, card| card.suit == trump.suit }
      pool = trumps.any? ? trumps : valued.select { |_seat, card| card.suit == led_suit }
      pool.max_by { |_seat, card| card.rank_value }.first
    end

    def to_h = plays.map { |seat, card| { seat:, card: card.to_s } }
  end
end
