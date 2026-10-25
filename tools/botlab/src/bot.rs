//! Mirrors app/models/hjerterfri/bot.rb: the three levels, Let ⊂ Mellem ⊂
//! Svær (docs/bots/hjerterfri-strategy.md). Method names follow the Ruby.
//!
//! Ruby semantics kept on purpose: `a - b` and `a & b` keep a's order;
//! min_by/max_by return the first extreme in enumeration order (legal
//! moves come in display order); sorts carry a full tie-break.

use crate::card::*;
use crate::knowledge::Knowledge;
use crate::params::{Level, Params, Rule};
use crate::rng::Rng;
use crate::round::{View, SEAT_COUNT};

pub const PASS_SIZE: usize = 3;
pub const QUEEN_GUARDS: usize = 3;
pub const LOW_SPADE: u8 = rank_index(b'J');
pub const LOW_HEART: u8 = rank_index(b'6');
pub const LOW_CARD: u8 = rank_index(b'7');
pub const TOP_HEARTS: [Card; 3] = [card(12, HEARTS), card(11, HEARTS), card(10, HEARTS)];
pub const MINOR_SUITS: [u8; 2] = [DIAMONDS, CLUBS];

pub struct Bot<'a> {
    pub level: Level,
    pub p: &'a Params,
    /// None: no variation (parity runs; Ruby's sample with rand(n) = 0).
    pub random: Option<Rng>,
}

fn highest_first(cards: &[Card]) -> Vec<Card> {
    let mut sorted = cards.to_vec();
    sorted.sort_by_key(|&c| (std::cmp::Reverse(rank(c)), suit(c)));
    sorted
}

fn highest(cards: impl IntoIterator<Item = Card>) -> Option<Card> {
    cards.into_iter().min_by_key(|&c| (std::cmp::Reverse(rank(c)), suit(c)))
}

fn lowest(cards: impl IntoIterator<Item = Card>) -> Option<Card> {
    cards.into_iter().min_by_key(|&c| (rank(c), suit(c)))
}

fn minus(a: &[Card], b: &[Card]) -> Vec<Card> {
    a.iter().copied().filter(|c| !b.contains(c)).collect()
}

fn and(a: &[Card], b: &[Card]) -> Vec<Card> {
    a.iter().copied().filter(|c| b.contains(c)).collect()
}

fn uniq_push(out: &mut Vec<Card>, cards: &[Card]) {
    for &c in cards {
        if out.len() == PASS_SIZE {
            return;
        }
        if !out.contains(&c) {
            out.push(c);
        }
    }
}

fn lower_spades(hand: &[Card]) -> usize {
    hand.iter().filter(|&&c| suit(c) == SPADES && rank(c) < rank(QUEEN)).count()
}
fn other_spades(hand: &[Card]) -> usize {
    hand.iter().filter(|&&c| suit(c) == SPADES && c != QUEEN).count()
}
fn low_spades(hand: &[Card]) -> usize {
    hand.iter().filter(|&&c| suit(c) == SPADES && rank(c) <= LOW_SPADE).count()
}
fn suit_length(hand: &[Card], s: u8) -> usize {
    hand.iter().filter(|&&c| suit(c) == s).count()
}
fn suit_strength(hand: &[Card], s: u8) -> u32 {
    hand.iter().filter(|&&c| suit(c) == s).map(|&c| rank(c) as u32).sum()
}

impl<'a> Bot<'a> {
    pub fn new(level: Level, p: &'a Params, random: Option<Rng>) -> Self {
        Bot { level, p, random }
    }

    fn mellem(&self) -> bool {
        self.level != Level::Let
    }
    fn svaer(&self) -> bool {
        self.level == Level::Svaer
    }
    fn on(&self, rule: Rule) -> bool {
        self.p.on(self.level, rule)
    }

    // ── Passing ─────────────────────────────────────────────────────────

    pub fn choose_pass(&self, hand: &[Card]) -> Vec<Card> {
        let picks = if self.level == Level::Let {
            self.let_pass(hand)
        } else if self.svaer() && self.on(Rule::Moon) && self.moon_hand(hand) {
            self.moon_pass(hand)
        } else {
            self.mellem_pass(hand)
        };
        let mut out = Vec::with_capacity(PASS_SIZE);
        uniq_push(&mut out, &picks);
        uniq_push(&mut out, &highest_first(hand));
        out
    }

    fn let_pass(&self, hand: &[Card]) -> Vec<Card> {
        let mut picks = Vec::new();
        let has_queen = hand.contains(&QUEEN);
        if has_queen && lower_spades(hand) < QUEEN_GUARDS {
            picks.push(QUEEN);
        }
        if !has_queen {
            picks.extend(highest_first(&and(hand, &HIGH_SPADES)));
        }
        let hearts: Vec<Card> = hand.iter().copied().filter(|&c| is_heart(c)).collect();
        picks.extend(highest_first(&hearts));
        let keep: Vec<Card> = if has_queen && !picks.contains(&QUEEN) { vec![QUEEN] } else { vec![] };
        picks.extend(highest_first(&minus(hand, &keep)));
        picks
    }

    fn mellem_pass(&self, hand: &[Card]) -> Vec<Card> {
        let mut picks = Vec::new();
        let has_queen = hand.contains(&QUEEN);
        if has_queen && other_spades(hand) < QUEEN_GUARDS {
            picks.push(QUEEN);
        }
        if !has_queen && low_spades(hand) < QUEEN_GUARDS {
            picks.extend(highest_first(&and(hand, &HIGH_SPADES)));
        }
        let room = PASS_SIZE as isize - picks.len() as isize;
        let void = MINOR_SUITS
            .iter()
            .map(|&s| hand.iter().copied().filter(|&c| suit(c) == s).collect::<Vec<_>>())
            .find(|cards| !cards.is_empty() && cards.len() as isize <= room);
        if let Some(void) = void {
            picks.extend(highest_first(&void));
        }
        picks.extend(highest_first(&and(hand, &TOP_HEARTS)));
        let mut kept: Vec<Card> = hand
            .iter()
            .copied()
            .filter(|&c| (suit(c) == SPADES && rank(c) <= LOW_SPADE) || (is_heart(c) && rank(c) <= LOW_HEART))
            .collect();
        if has_queen && !picks.contains(&QUEEN) {
            kept.push(QUEEN);
        }
        let mut rest = minus(hand, &kept);
        rest.sort_by_key(|&c| (std::cmp::Reverse(rank(c)), std::cmp::Reverse(suit_length(hand, suit(c))), suit(c)));
        picks.extend(rest);
        picks
    }

    fn moon_pass(&self, hand: &[Card]) -> Vec<Card> {
        let mut others: Vec<Card> = hand.iter().copied().filter(|&c| !is_heart(c) && c != QUEEN).collect();
        others.sort_by_key(|&c| (suit_strength(hand, suit(c)), rank(c), suit(c)));
        others
    }

    pub fn moon_hand(&self, hand: &[Card]) -> bool {
        if !TOP_HEARTS.iter().all(|c| hand.contains(c)) {
            return false;
        }
        if hand.contains(&QUEEN) && other_spades(hand) < QUEEN_GUARDS {
            return false;
        }
        let hearts = hand.iter().filter(|&&c| is_heart(c)).count();
        let long_with_ace = [CLUBS, DIAMONDS, SPADES].iter().any(|&s| suit_length(hand, s) >= 6 && hand.contains(&card(12, s)));
        hearts >= 6 || long_with_ace
    }

    // ── Playing ─────────────────────────────────────────────────────────

    pub fn choose_play(&mut self, view: &View, totals: Option<[i32; SEAT_COUNT]>, end_score: Option<i32>) -> Card {
        let known = Knowledge::new(view, self.level, self.p, totals, end_score);
        let legal = known.legal;
        if legal.len() == 1 {
            return legal[0];
        }
        let c = if known.leading() {
            self.lead(&known)
        } else if Some(suit(legal[0])) == known.led_suit {
            self.follow(&known)
        } else {
            self.discard(&known)
        };
        self.vary(c, &known)
    }

    /// true = "add_to_others"
    pub fn choose_moon(&self, seat: usize, totals: &[i32; SEAT_COUNT]) -> bool {
        totals[seat] <= *totals.iter().min().unwrap()
    }

    // ── Leading ─────────────────────────────────────────────────────────

    fn lead(&self, known: &Knowledge) -> Card {
        let legal = known.legal;
        if self.svaer() {
            if self.shooting_moon(known) {
                return highest(legal.iter().copied()).unwrap();
            }
            if let Some(late) = self.late_lead(known) {
                return late;
            }
            if let Some(safe_high) = self.safe_high_lead(known) {
                return safe_high;
            }
            if self.on(Rule::QueenHunt) {
                if let Some(holder) = known.queen_holder() {
                    if holder != known.me {
                        if let Some(c) = lowest(legal.iter().copied().filter(|&c| suit(c) == SPADES && rank(c) < rank(QUEEN))) {
                            return c;
                        }
                    }
                }
            }
        }

        if self.mellem() {
            if let Some(void_plan) = self.void_plan_lead(known) {
                return void_plan;
            }
            if self.on(Rule::QueenChase) && known.queen_out() && ![QUEEN, KING_OF_SPADES, ACE_OF_SPADES].iter().any(|&c| known.in_hand(c)) {
                if let Some(spade) = lowest(legal.iter().copied().filter(|&c| suit(c) == SPADES && rank(c) < rank(QUEEN))) {
                    return spade;
                }
            }
        }

        self.let_lead(known)
    }

    fn let_lead(&self, known: &Knowledge) -> Card {
        let legal = known.legal;
        let mut safe: Vec<Card> = legal.iter().copied().filter(|&c| !self.dangerous(c, known)).collect();
        if safe.is_empty() {
            safe = legal.to_vec();
        }
        safe.iter()
            .copied()
            .min_by_key(|&c| (is_penalty(c) as u8, self.high_and_risky(c, known) as u8, rank(c), suit(c)))
            .unwrap()
    }

    fn high_and_risky(&self, c: Card, known: &Knowledge) -> bool {
        self.on(Rule::Risk) && rank(c) >= self.p.high && known.risky(suit(c))
    }

    fn void_plan_lead(&self, known: &Knowledge) -> Option<Card> {
        if !self.on(Rule::VoidPlan) || known.hand.len() < self.p.void_plan_hand || known.hearts_broken() {
            return None;
        }
        let suits: Vec<Vec<Card>> = MINOR_SUITS
            .iter()
            .map(|&s| known.legal.iter().copied().filter(|&c| suit(c) == s).collect::<Vec<_>>())
            .filter(|cards| !cards.is_empty() && cards.len() <= PASS_SIZE && !known.risky(suit(cards[0])))
            .collect();
        let mut shortest: Option<&Vec<Card>> = None;
        for cards in &suits {
            if shortest.map_or(true, |s| cards.len() < s.len()) {
                shortest = Some(cards);
            }
        }
        shortest.and_then(|cards| highest(cards.iter().copied()))
    }

    fn late_lead(&self, known: &Knowledge) -> Option<Card> {
        if !self.on(Rule::Late) || !known.late() {
            return None;
        }
        highest(known.legal.iter().copied().filter(|&c| known.exit(c) && !self.dangerous(c, known)))
    }

    fn safe_high_lead(&self, known: &Knowledge) -> Option<Card> {
        if !self.on(Rule::SafeHigh) || known.late() || known.hand.len() > self.p.safe_high_hand {
            return None;
        }
        highest(known.legal.iter().copied().filter(|&c| {
            !is_heart(c)
                && !(suit(c) == SPADES && known.queen_out())
                && known.top(c)
                && !known.anyone_else_void(suit(c))
                && known.safe(suit(c))
        }))
    }

    // ── Following suit ──────────────────────────────────────────────────

    fn follow(&self, known: &Knowledge) -> Card {
        let legal = known.legal;
        let winning = known.winning_card();
        let winners: Vec<Card> = legal.iter().copied().filter(|&c| rank(c) > rank(winning)).collect();
        let losers = minus(legal, &winners);

        if self.svaer() && self.shooting_moon(known) && !winners.is_empty() {
            return highest(legal.iter().copied()).unwrap();
        }

        if let Some(blocker) = self.block_moon(known, &winners) {
            return blocker;
        }

        if let Some(jack) = self.take_jack(known, &winners) {
            return jack;
        }

        if self.mellem() && known.led_suit == Some(DIAMONDS) && known.jack_rule() && !losers.is_empty() && self.jack_out(known) {
            return lowest(losers.iter().copied()).unwrap();
        }

        if self.mellem() && self.on(Rule::Shed) && !winners.is_empty() && self.clean_and_safe(known) {
            let shed = highest(winners.iter().copied().filter(|&c| !(c == QUEEN || (c == JACK_OF_DIAMONDS && known.jack_rule()))));
            if let Some(shed) = shed {
                return shed;
            }
        }

        if !losers.is_empty() {
            return highest(losers.iter().copied().filter(|&c| !self.avoid_jack(c, known)))
                .or_else(|| highest(losers.iter().copied()))
                .unwrap();
        }

        let mut others = minus(legal, &[QUEEN]);
        if others.is_empty() {
            others = legal.to_vec();
        }
        if known.last_to_play() {
            highest(others).unwrap()
        } else {
            lowest(others).unwrap()
        }
    }

    fn clean_and_safe(&self, known: &Knowledge) -> bool {
        if known.trick_points() > 0 {
            return false;
        }
        if known.last_to_play() {
            return true;
        }
        known.led_suit == Some(SPADES) && (known.queen_played() || self.queen_holder_has_played(known))
    }

    fn queen_holder_has_played(&self, known: &Knowledge) -> bool {
        match known.queen_holder() {
            Some(holder) => known.trick.iter().any(|play| play.seat == holder),
            None => false,
        }
    }

    fn block_moon(&self, known: &Knowledge, winners: &[Card]) -> Option<Card> {
        known.moon_threat()?;
        if winners.is_empty() || known.trick_points() <= 0 {
            return None;
        }
        if known.over_with(known.me, known.trick_points() + 13) {
            return None;
        }
        lowest(winners.iter().copied())
    }

    fn take_jack(&self, known: &Knowledge, winners: &[Card]) -> Option<Card> {
        if !(known.jack_rule() && known.trick_has(JACK_OF_DIAMONDS) && known.trick_points() == 0) {
            return None;
        }
        lowest(winners.iter().copied().filter(|&c| suit(c) == DIAMONDS))
    }

    fn jack_out(&self, known: &Knowledge) -> bool {
        !known.played(JACK_OF_DIAMONDS) && !known.in_hand(JACK_OF_DIAMONDS)
    }

    fn avoid_jack(&self, c: Card, known: &Knowledge) -> bool {
        c == JACK_OF_DIAMONDS && known.jack_rule()
    }

    // ── Discarding (void in the led suit) ───────────────────────────────

    fn discard(&self, known: &Knowledge) -> Card {
        let legal = known.legal;
        if self.svaer() && self.shooting_moon(known) {
            return lowest(legal.iter().copied().filter(|&c| !is_penalty(c))).or_else(|| lowest(legal.iter().copied())).unwrap();
        }

        let winner = known.winning_play().seat;
        if !self.feed(known, winner) {
            if let Some(c) = highest(legal.iter().copied().filter(|&c| !is_penalty(c))) {
                return c;
            }
        }

        if legal.contains(&QUEEN) {
            return QUEEN;
        }

        let hearts: Vec<Card> = legal.iter().copied().filter(|&c| is_heart(c)).collect();
        if !hearts.is_empty() && !self.mellem() {
            return highest(hearts).unwrap();
        }
        if !self.mellem() {
            return highest(legal.iter().copied()).unwrap();
        }

        let high_spades = and(legal, &HIGH_SPADES);
        if !high_spades.is_empty() && known.queen_out() {
            return highest(high_spades).unwrap();
        }

        if !hearts.is_empty() {
            return highest(hearts).unwrap();
        }

        self.shed_from_short_suit(known)
    }

    fn feed(&self, known: &Knowledge, winner: usize) -> bool {
        if !self.on(Rule::Feed) {
            return true;
        }
        if known.moon_threat() == Some(winner) {
            return false;
        }
        if !known.scores() {
            return true;
        }
        let pts = if known.legal.contains(&QUEEN) { 13 } else { 1 };
        !(known.over_with(winner, pts) && !known.lowest())
    }

    fn shed_from_short_suit(&self, known: &Knowledge) -> Card {
        let legal = known.legal;
        let keep: Vec<Card> = if known.moon_threat().is_some() { highest_first(legal).into_iter().take(2).collect() } else { vec![] };
        let mut candidates = minus(legal, &keep);
        if candidates.is_empty() {
            candidates = legal.to_vec();
        }
        if self.svaer() && self.on(Rule::TwoLowSuits) {
            candidates = self.keep_two_low_suits(candidates, known);
        }
        // max_by [-suit_length, rank]: the first maximum in legal order.
        let key = |c: Card| (-(suit_length(known.hand, suit(c)) as i32), rank(c));
        let mut best = candidates[0];
        for &c in &candidates[1..] {
            if key(c) > key(best) {
                best = c;
            }
        }
        best
    }

    fn keep_two_low_suits(&self, candidates: Vec<Card>, known: &Knowledge) -> Vec<Card> {
        let mut low_suits: Vec<u8> = Vec::new();
        for &c in known.hand {
            if rank(c) <= LOW_CARD && !low_suits.contains(&suit(c)) {
                low_suits.push(suit(c));
            }
        }
        if low_suits.len() > 2 {
            return candidates;
        }
        let spared: Vec<Card> = candidates
            .iter()
            .copied()
            .filter(|&c| {
                !(rank(c) <= LOW_CARD && known.hand.iter().filter(|&&o| suit(o) == suit(c) && rank(o) <= LOW_CARD).count() == 1)
            })
            .collect();
        if spared.is_empty() {
            candidates
        } else {
            spared
        }
    }

    // ── The moon (Svær) ─────────────────────────────────────────────────

    fn shooting_moon(&self, known: &Knowledge) -> bool {
        if !self.svaer() || !self.on(Rule::Moon) {
            return false;
        }
        if known.others().any(|seat| known.penalty_taken(seat) > 0) {
            return false;
        }
        if known.scores() && known.total(known.me) + 26 >= known.end_score.unwrap() && !known.lowest() {
            return false;
        }
        self.moon_hand(&known.hand_after_pass())
    }

    // ── Variation (spec §3) ─────────────────────────────────────────────

    fn vary(&mut self, c: Card, known: &Knowledge) -> Card {
        if self.random.is_none() {
            return c;
        }
        let peers: Vec<Card> = known
            .legal
            .iter()
            .copied()
            .filter(|&other| {
                other != c
                    && suit(other) == suit(c)
                    && self.same_role(other, c, known)
                    && if self.svaer() { known.equivalent(c, other) } else { (rank(other) as i32 - rank(c) as i32).abs() == 1 }
            })
            .collect();
        if peers.is_empty() {
            return c;
        }
        let n = peers.len() + 1;
        let i = self.random.as_mut().unwrap().below(n);
        if i == 0 {
            c
        } else {
            peers[i - 1]
        }
    }

    fn same_role(&self, other: Card, c: Card, known: &Knowledge) -> bool {
        let special = [QUEEN, KING_OF_SPADES, ACE_OF_SPADES, JACK_OF_DIAMONDS];
        if special.contains(&other) || special.contains(&c) {
            return false;
        }
        if points(other) != points(c) {
            return false;
        }
        if known.leading() || known.led_suit != Some(suit(c)) {
            return true;
        }
        let winning = rank(known.winning_card());
        (rank(other) > winning) == (rank(c) > winning)
    }

    // ── Helpers ─────────────────────────────────────────────────────────

    fn dangerous(&self, c: Card, known: &Knowledge) -> bool {
        c == QUEEN || (HIGH_SPADES.contains(&c) && known.queen_out())
    }
}
