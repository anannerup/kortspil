"""The es-makker deck as small ints (Esmakker::Card, Joker).

A playing card is suit * 13 + rank: suits C D H S (0-3, Card::SUITS order),
ranks 2 3 4 5 6 7 8 9 T J Q K A (0-12). The three jokers X1, X2, X3 are
52, 53, 54. A set of cards (a hand) is an int bitmask: bit c is card c.
"""

SUITS = "CDHS"
RANKS = "23456789TJQKA"
SEAT_COUNT = 4
HAND_SIZE = 13
KITTY_SIZE = 3
DECK_SIZE = 55
ACE_RANK = 12
JOKERS = (52, 53, 54)
CLUBS = 0

SUIT_MASK = tuple(((1 << 13) - 1) << (13 * suit) for suit in range(4))
JOKER_MASK = 0b111 << 52
# The number cards 2-10 (ranks 0-8) of every suit: a jernhånd holds only these.
NUMBER_MASK = sum(((1 << 9) - 1) << (13 * suit) for suit in range(4))


def suit_of(card):
    """The card's suit 0-3, or -1 for a joker."""
    return card // 13 if card < 52 else -1


def rank_of(card):
    return card % 13


def is_joker(card):
    return card >= 52


def ace(suit):
    return suit * 13 + ACE_RANK


def code(card):
    """The Ruby card code: "2C", "TD", "AS", "X1"."""
    if card >= 52:
        return f"X{card - 51}"
    return RANKS[card % 13] + SUITS[card // 13]


def parse(text):
    if len(text) == 2 and text[0] == "X" and text[1] in "123":
        return 51 + int(text[1])
    if len(text) != 2 or text[0] not in RANKS or text[1] not in SUITS:
        raise ValueError(f"not a card code: {text!r}")
    return SUITS.index(text[1]) * 13 + RANKS.index(text[0])


def mask(cards):
    result = 0
    for card in cards:
        result |= 1 << card
    return result


def cards_of(bits):
    """The cards of a bitmask, lowest int first."""
    out = []
    while bits:
        low = bits & -bits
        out.append(low.bit_length() - 1)
        bits ^= low
    return out


def parse_deal(text):
    """A Ruby deal string (55 codes: four hands of 13, then the kitty)."""
    cards = [parse(part) for part in text.split()]
    if len(cards) != DECK_SIZE or len(set(cards)) != DECK_SIZE:
        raise ValueError("a deal is 55 different cards")
    return cards


def deal_string(deal):
    return " ".join(code(card) for card in deal)
