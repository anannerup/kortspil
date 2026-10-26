module Esmakker
  class Svaer
    # Svær works on cards as small integers, as the Python port does
    # (tools/esmakker_ai/esmakker_ai/cards.py), so the two break every tie
    # alike: suit × 13 + rank, suits C D H S (0–3), ranks 2 … A (0–12),
    # the jokers 52–54; the fordækt card played face down is FACE_DOWN.
    # Trump is a suit 0–3 or NT (4). Meldinger are ints too
    # (meldinger.py): (number − 8) × 4 + påhæng (gode 1, halve 2, vip 3),
    # the sol-meldinger 24–27.
    module Cards
      NT = 4
      FACE_DOWN = -1
      ACE = 12
      KING = 11
      QUEEN = 10
      JACK = 9
      DECK_SIZE = 55
      SOL = 24
      REN_SOL = 25
      BORDLAEGGER = 26
      REN_BORDLAEGGER = 27
      SOL_KINDS = %w[sol ren_sol bordlaegger ren_bordlaegger].freeze
      PAHAENG = [ nil, :gode, :halve, :vip ].freeze

      module_function

      def suit(card) = card.between?(0, 51) ? card / 13 : -1
      def rank(card) = card % 13
      def joker?(card) = card >= 52
      def ace(suit) = suit * 13 + ACE
      def ranks_in(hand, suit) = hand.select { |card| suit(card) == suit }.map { |card| rank(card) }.sort
      def cards_in(hand, suit) = hand.select { |card| suit(card) == suit }.sort

      # A card's height at a sol-melding: es 1, 2 … K 13.
      def sol_value(card) = rank(card) == ACE ? 1 : rank(card) + 2

      def int(code)
        return FACE_DOWN if code.nil? || code == Play::FACE_DOWN

        card = Card.parse(code)
        card.joker? ? 51 + card.number : Card::SUITS.index(card.suit) * 13 + card.rank_value
      end

      def card(int) = int >= 52 ? Joker.new(number: int - 51) : Card.new(rank: Card::RANKS[int % 13], suit: Card::SUITS[int / 13])
      def code(int) = card(int).to_s

      def suit_index(letter) = letter && Card::SUITS.index(letter)
      def trump_int(code) = code.nil? ? nil : (code == Trump::TRUMFLOES ? NT : Card::SUITS.index(code))
      def trump_code(int) = int == NT ? Trump::TRUMFLOES : Card::SUITS[int]

      def melding_int(code)
        return nil if code.nil?

        melding = Melding.parse(code)
        return SOL + SOL_KINDS.index(melding.kind.to_s) if melding.sol_melding?

        (melding.number - 8) * 4 + PAHAENG.index(melding.pahaeng)
      end

      def melding_code(int)
        return SOL_KINDS[int - SOL] if int >= SOL

        "#{number(int)}#{PAHAENG[int % 4]}"
      end

      def sol?(melding) = melding >= SOL
      def number(melding) = melding / 4 + 8
      def pahaeng(melding) = melding >= SOL ? -1 : melding % 4

      # An estimate for the thought: an Integer when whole, else a Float.
      def num(value)
        return nil if value.nil?

        value = Rational(value)
        value.denominator == 1 ? value.to_i : value.to_f
      end
    end
  end
end
