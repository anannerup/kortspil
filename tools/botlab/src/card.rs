//! Mirrors app/models/hjerterfri/card.rb. A card is one byte:
//! suit index * 13 + rank index, with RANKS 2..A and SUITS C D H S, so the
//! byte order is Card.deck's order.

pub type Card = u8;

pub const RANKS: &[u8; 13] = b"23456789TJQKA";
pub const SUITS: &[u8; 4] = b"CDHS";
pub const CLUBS: u8 = 0;
pub const DIAMONDS: u8 = 1;
pub const HEARTS: u8 = 2;
pub const SPADES: u8 = 3;

pub const fn card(rank: u8, suit: u8) -> Card {
    suit * 13 + rank
}
pub const fn rank(card: Card) -> u8 {
    card % 13
}
pub const fn suit(card: Card) -> u8 {
    card / 13
}

pub const fn rank_index(ch: u8) -> u8 {
    let mut i = 0;
    while i < 13 {
        if RANKS[i] == ch {
            return i as u8;
        }
        i += 1;
    }
    panic!("not a rank")
}

pub const TWO_OF_CLUBS: Card = card(0, CLUBS);
pub const JACK_OF_DIAMONDS: Card = card(rank_index(b'J'), DIAMONDS);
pub const QUEEN: Card = card(rank_index(b'Q'), SPADES);
pub const KING_OF_SPADES: Card = card(rank_index(b'K'), SPADES);
pub const ACE_OF_SPADES: Card = card(rank_index(b'A'), SPADES);
/// Knowledge::HIGH_SPADES = [K♠, A♠]
pub const HIGH_SPADES: [Card; 2] = [KING_OF_SPADES, ACE_OF_SPADES];

pub fn deck() -> impl Iterator<Item = Card> {
    0..52u8
}

pub fn is_heart(card: Card) -> bool {
    suit(card) == HEARTS
}

pub fn points(card: Card) -> i32 {
    if is_heart(card) {
        1
    } else if card == QUEEN {
        13
    } else {
        0
    }
}

pub fn is_penalty(card: Card) -> bool {
    points(card) > 0
}

/// Hands are shown clubs, diamonds, spades, hearts; then by rank.
pub fn display_key(card: Card) -> (u8, u8) {
    let display_suit = match suit(card) {
        CLUBS => 0,
        DIAMONDS => 1,
        SPADES => 2,
        _ => 3,
    };
    (display_suit, rank(card))
}

pub fn in_display_order(cards: &mut [Card]) {
    cards.sort_by_key(|&c| display_key(c));
}

pub fn parse(code: &str) -> Option<Card> {
    let b = code.as_bytes();
    if b.len() != 2 {
        return None;
    }
    let r = RANKS.iter().position(|&x| x == b[0])? as u8;
    let s = SUITS.iter().position(|&x| x == b[1])? as u8;
    Some(card(r, s))
}

pub fn to_s(card: Card) -> String {
    let mut s = String::with_capacity(2);
    s.push(RANKS[rank(card) as usize] as char);
    s.push(SUITS[suit(card) as usize] as char);
    s
}

