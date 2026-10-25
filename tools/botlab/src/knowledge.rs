//! Mirrors app/models/hjerterfri/bot/knowledge.rb: what a seat knows when
//! it is to play, limited by the bot's level (spec §2).

use crate::card::*;
use crate::params::{Level, Params, Rule};
use crate::round::{DoneTrick, PassDirection, Play, Rules, View, SEAT_COUNT};

/// Ruby's Array#sum over floats: Kahan-Babuska compensated summation,
/// so sums come out bit-for-bit as in Ruby.
pub fn ruby_sum(values: impl Iterator<Item = f64>) -> f64 {
    let mut f = 0.0f64;
    let mut c = 0.0f64;
    for x in values {
        let t = f + x;
        if f.abs() >= x.abs() {
            c += (f - t) + x;
        } else {
            c += (x - t) + f;
        }
        f = t;
    }
    f + c
}

fn mask(cards: &[Card]) -> u64 {
    cards.iter().fold(0u64, |m, &c| m | (1u64 << c))
}

pub struct Knowledge<'a> {
    pub level: Level,
    pub p: &'a Params,
    pub me: usize,
    pub hand: &'a [Card],
    pub legal: &'a [Card],
    pub trick: &'a [Play],
    pub led_suit: Option<u8>,
    tricks: &'a [DoneTrick],
    rules: Rules,
    hearts_broken: bool,
    pass_direction: PassDirection,
    own_pass: &'a [Card],
    card_counts: [usize; SEAT_COUNT],
    pub totals: Option<[i32; SEAT_COUNT]>,
    pub end_score: Option<i32>,
    hand_mask: u64,
    /// Knowledge#played as a set (empty for Let).
    played_mask: u64,
    shown_void: [[bool; 4]; SEAT_COUNT],
    queen_holder: Option<usize>,
    queen_odds: [f64; SEAT_COUNT],
    penalty_taken: [i32; SEAT_COUNT],
}

impl<'a> Knowledge<'a> {
    pub fn new(view: &'a View, level: Level, p: &'a Params, totals: Option<[i32; SEAT_COUNT]>, end_score: Option<i32>) -> Self {
        let mut k = Knowledge {
            level,
            p,
            me: view.seat,
            hand: &view.hand,
            legal: &view.legal,
            trick: &view.trick,
            led_suit: view.trick.first().map(|play| suit(play.card)),
            tricks: &view.tricks,
            rules: view.rules,
            hearts_broken: view.hearts_broken,
            pass_direction: view.pass_direction,
            own_pass: &view.own_pass,
            card_counts: view.card_counts,
            totals,
            end_score,
            hand_mask: mask(&view.hand),
            played_mask: 0,
            shown_void: [[false; 4]; SEAT_COUNT],
            queen_holder: None,
            queen_odds: [0.0; SEAT_COUNT],
            penalty_taken: [0; SEAT_COUNT],
        };
        let mut played = 0u64;
        for plays in k.all_tricks() {
            let led = suit(plays[0].card);
            for play in plays {
                played |= 1u64 << play.card;
                if suit(play.card) != led {
                    k.shown_void[play.seat][led as usize] = true;
                }
            }
        }
        if k.mellem() {
            k.played_mask = played;
        }
        for done in k.tricks {
            k.penalty_taken[done.winner] += done.plays.iter().map(|play| points(play.card)).sum::<i32>();
        }
        k.queen_holder = k.find_queen_holder();
        k.queen_odds = k.compute_queen_odds();
        k
    }

    pub fn mellem(&self) -> bool {
        self.level != Level::Let
    }
    pub fn svaer(&self) -> bool {
        self.level == Level::Svaer
    }
    pub fn on(&self, rule: Rule) -> bool {
        self.p.on(self.level, rule)
    }

    pub fn leading(&self) -> bool {
        self.trick.is_empty()
    }
    pub fn hearts_broken(&self) -> bool {
        self.hearts_broken
    }
    pub fn last_to_play(&self) -> bool {
        self.trick.len() == SEAT_COUNT - 1
    }
    pub fn late(&self) -> bool {
        self.hand.len() <= self.p.late
    }
    pub fn jack_rule(&self) -> bool {
        self.mellem() && self.rules.jack_of_diamonds_minus_ten && self.on(Rule::Jack)
    }

    /// The play winning the current stik so far.
    pub fn winning_play(&self) -> Play {
        let led = self.led_suit.unwrap();
        let mut best = self.trick[0];
        for &play in self.trick {
            if suit(play.card) == led && rank(play.card) > rank(best.card) {
                best = play;
            }
        }
        best
    }
    pub fn winning_card(&self) -> Card {
        self.winning_play().card
    }
    pub fn trick_points(&self) -> i32 {
        self.trick.iter().map(|play| points(play.card)).sum()
    }
    pub fn trick_has(&self, card: Card) -> bool {
        self.trick.iter().any(|play| play.card == card)
    }

    pub fn played(&self, card: Card) -> bool {
        self.played_mask & (1u64 << card) != 0
    }
    pub fn in_hand(&self, card: Card) -> bool {
        self.hand_mask & (1u64 << card) != 0
    }

    pub fn queen_mine(&self) -> bool {
        self.in_hand(QUEEN)
    }
    pub fn queen_played(&self) -> bool {
        self.played(QUEEN)
    }
    /// Let assumes Q♠ is out unless it holds it.
    pub fn queen_out(&self) -> bool {
        !self.queen_mine() && !self.queen_played()
    }
    pub fn queen_holder(&self) -> Option<usize> {
        self.queen_holder
    }
    pub fn queen_odds(&self, seat: usize) -> f64 {
        self.queen_odds[seat]
    }

    fn compute_queen_odds(&self) -> [f64; SEAT_COUNT] {
        let mut odds = [0.0; SEAT_COUNT];
        if self.queen_mine() || self.queen_played() {
            return odds;
        }
        if let Some(holder) = self.queen_holder {
            odds[holder] = 1.0;
            return odds;
        }
        let mut weights = [0.0; SEAT_COUNT];
        for seat in self.others() {
            let mut weight = if self.shown_void(seat, SPADES) { 0.0 } else { 1.0 };
            if self.svaer() && self.on(Rule::Counting) {
                weight *= self.unknown_count(seat) as f64;
            }
            if self.mellem() {
                weight *= self.queen_evidence(seat);
            }
            weights[seat] = weight;
        }
        let sum = ruby_sum(self.others().map(|seat| weights[seat]));
        if sum == 0.0 {
            return odds;
        }
        for seat in self.others() {
            odds[seat] = weights[seat] / sum;
        }
        odds
    }

    /// Expected penalty points dropped on the seat if it takes a stik in
    /// `suit`, from the seats in `after`.
    pub fn dump_risk(&self, suit_: u8, after: &[usize]) -> f64 {
        ruby_sum(after.iter().map(|&seat| {
            let void = self.void_chance(seat, suit_);
            if void == 0.0 {
                return 0.0;
            }
            let queen = if suit_ == SPADES { 0.0 } else { self.queen_odds(seat) * 13.0 };
            let hearts = if suit_ == HEARTS || self.void_chance(seat, HEARTS) == 1.0 { 0.0 } else { 1.0 };
            void * (queen + hearts)
        }))
    }

    pub fn risky(&self, suit_: u8) -> bool {
        self.dump_risk(suit_, &self.seats_after_me()) >= self.p.risky
    }

    pub fn void_chance(&self, seat: usize, suit_: u8) -> f64 {
        if self.shown_void(seat, suit_) {
            return 1.0;
        }
        if !self.mellem() {
            return 0.0;
        }
        self.void_odds(seat, suit_)
    }

    pub fn seats_after_me(&self) -> Vec<usize> {
        if self.leading() {
            return self.others().collect();
        }
        (1..(SEAT_COUNT - self.trick.len())).map(|step| (self.me + step) % SEAT_COUNT).collect()
    }

    pub fn penalty_taken(&self, seat: usize) -> i32 {
        self.penalty_taken[seat]
    }

    pub fn moon_threat(&self) -> Option<usize> {
        if !self.mellem() || !self.on(Rule::BlockMoon) {
            return None;
        }
        let takers: Vec<usize> = (0..SEAT_COUNT).filter(|&s| self.penalty_taken[s] > 0).collect();
        if takers.len() == 1 && takers[0] != self.me && self.penalty_taken[takers[0]] >= self.p.moon_threat {
            Some(takers[0])
        } else {
            None
        }
    }

    pub fn void(&self, seat: usize, suit_: u8) -> bool {
        self.mellem() && self.shown_void(seat, suit_)
    }

    pub fn shown_void(&self, seat: usize, suit_: u8) -> bool {
        self.shown_void[seat][suit_ as usize]
    }

    pub fn void_odds(&self, seat: usize, suit_: u8) -> f64 {
        if self.shown_void(seat, suit_) {
            return 1.0;
        }
        let counting = self.svaer() && self.on(Rule::Counting);
        if counting && self.known_cards(seat).iter().any(|&c| suit(c) == suit_) {
            return 0.0;
        }
        let unknown = self.outstanding(suit_).filter(|&c| !counting || !self.placed(c)).count() as i64;
        if unknown == 0 {
            return 1.0;
        }
        let count = |other: usize| -> i64 { if counting { self.unknown_count(other) as i64 } else { self.hand.len() as i64 } };
        let pool: i64 = self.others().filter(|&o| !self.shown_void(o, suit_)).map(count).sum();
        let mine = count(seat);
        (0..unknown).fold(1.0f64, |odds, index| {
            if pool - index <= 0 {
                0.0
            } else {
                odds * ((pool - mine - index).max(0) as f64) / ((pool - index) as f64)
            }
        })
    }

    pub fn void_or_likely(&self, seat: usize, suit_: u8) -> bool {
        self.void(seat, suit_) || (self.svaer() && self.void_odds(seat, suit_) >= 0.5)
    }

    pub fn anyone_else_void(&self, suit_: u8) -> bool {
        self.others().any(|seat| self.void_or_likely(seat, suit_))
    }

    /// Cards of the suit still in other hands, in deck order.
    pub fn outstanding(&self, suit_: u8) -> impl Iterator<Item = Card> + '_ {
        (0..13).map(move |r| card(r, suit_)).filter(move |&c| !self.played(c) && !self.in_hand(c))
    }

    pub fn top(&self, c: Card) -> bool {
        !self.outstanding(suit(c)).any(|o| rank(o) > rank(c))
    }

    pub fn exit(&self, c: Card) -> bool {
        self.outstanding(suit(c)).any(|o| rank(o) > rank(c)) && self.others().any(|seat| !self.void_or_likely(seat, suit(c)))
    }

    pub fn equivalent(&self, a: Card, b: Card) -> bool {
        let (low, high) = (rank(a).min(rank(b)), rank(a).max(rank(b)));
        ((low + 1)..high).all(|r| {
            let between = card(r, suit(a));
            self.played(between) || self.in_hand(between)
        })
    }

    /// The hand the seat had after the pass: what it holds and has played.
    pub fn hand_after_pass(&self) -> Vec<Card> {
        let mut cards = self.hand.to_vec();
        for plays in self.all_tricks() {
            for play in plays {
                if play.seat == self.me {
                    cards.push(play.card);
                }
            }
        }
        cards
    }

    pub fn scores(&self) -> bool {
        self.svaer() && self.totals.is_some() && self.end_score.is_some() && self.on(Rule::Scores)
    }
    pub fn lowest(&self) -> bool {
        self.scores() && {
            let t = self.totals.unwrap();
            t[self.me] <= *t.iter().min().unwrap()
        }
    }
    pub fn over_with(&self, seat: usize, pts: i32) -> bool {
        self.scores() && self.totals.unwrap()[seat] + pts >= self.end_score.unwrap()
    }
    pub fn total(&self, seat: usize) -> i32 {
        self.totals.unwrap()[seat]
    }

    pub fn others(&self) -> impl Iterator<Item = usize> + '_ {
        let me = self.me;
        (0..SEAT_COUNT).filter(move |&s| s != me)
    }

    fn find_queen_holder(&self) -> Option<usize> {
        if self.queen_mine() || self.queen_played() {
            return None;
        }
        if self.mellem() && self.own_pass.contains(&QUEEN) {
            return Some(PassDirection::receiver(self.me, self.pass_direction));
        }
        let candidates: Vec<usize> = self.others().filter(|&s| !self.shown_void(s, SPADES)).collect();
        if candidates.len() == 1 {
            Some(candidates[0])
        } else {
            None
        }
    }

    /// Cards passed to `seat` that are not played yet (Mellem and Svær).
    fn known_cards(&self, seat: usize) -> Vec<Card> {
        if !self.mellem() || self.own_pass.is_empty() || seat != PassDirection::receiver(self.me, self.pass_direction) {
            return Vec::new();
        }
        self.own_pass.iter().copied().filter(|&c| !self.played(c)).collect()
    }

    fn placed(&self, c: Card) -> bool {
        self.others().any(|seat| self.known_cards(seat).contains(&c))
    }

    fn unknown_count(&self, seat: usize) -> usize {
        self.card_counts[seat].saturating_sub(self.known_cards(seat).len())
    }

    fn queen_evidence(&self, seat: usize) -> f64 {
        self.all_tricks().fold(1.0, |weight, plays| {
            let Some(index) = plays.iter().position(|play| play.seat == seat) else { return weight };
            let c = plays[index].card;
            let led = suit(plays[0].card);
            if suit(c) != led {
                if self.on(Rule::Evidence) { weight * self.p.discard_evidence } else { weight }
            } else if self.svaer()
                && self.on(Rule::SpadeEvidence)
                && led == SPADES
                && c != QUEEN
                && plays[..index].iter().any(|o| suit(o.card) == SPADES && rank(o.card) > rank(QUEEN))
            {
                weight * self.p.spade_evidence
            } else {
                weight
            }
        })
    }

    fn all_tricks(&self) -> impl Iterator<Item = &'a [Play]> {
        let current: Option<&'a [Play]> = if self.trick.is_empty() { None } else { Some(self.trick) };
        self.tricks.iter().map(|done| done.plays.as_slice()).chain(current)
    }
}
