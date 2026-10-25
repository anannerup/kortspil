//! Mirrors app/models/hjerterfri/bot.rb: the three levels, Let ⊂ Mellem ⊂
//! Svær (docs/bots/hjerterfri-strategy.md). Method names follow the Ruby.
//!
//! Ruby semantics kept on purpose: `a - b` and `a & b` keep a's order;
//! min_by/max_by return the first extreme in enumeration order (legal
//! moves come in display order); sorts carry a full tie-break.

use crate::card::*;
use crate::knowledge::{Knowledge, JACK_POINTS};
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
    /// The rule behind the last play (botlab regret only).
    pub why: std::cell::Cell<&'static str>,
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
        Bot { level, p, random, why: std::cell::Cell::new("") }
    }

    fn w<T>(&self, why: &'static str, value: T) -> T {
        self.why.set(why);
        value
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
        let guards = if self.svaer() { self.p.svaer_queen_guards } else { QUEEN_GUARDS };
        let mut picks = Vec::new();
        let has_queen = hand.contains(&QUEEN);
        if has_queen && other_spades(hand) < guards {
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
        if self.svaer() && self.on(Rule::LowCover) {
            // Svær: high cards from the suits with the fewest low cards first.
            let lows = |s: u8| hand.iter().filter(|&&c| suit(c) == s && rank(c) <= LOW_CARD).count();
            rest.sort_by_key(|&c| (lows(suit(c)), std::cmp::Reverse(rank(c)), std::cmp::Reverse(suit_length(hand, suit(c))), suit(c)));
        } else {
            rest.sort_by_key(|&c| (std::cmp::Reverse(rank(c)), std::cmp::Reverse(suit_length(hand, suit(c))), suit(c)));
        }
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
            self.why.set("forced");
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
                return self.w("lead:moon", highest(legal.iter().copied()).unwrap());
            }
            if self.on(Rule::QueenHunt) {
                if let Some(holder) = known.queen_holder() {
                    if holder != known.me {
                        // Press with the highest spade under Q♠ (J♠, 10♠, ...); low spades stay as the bot's own guard (Anders, 2026-10-25).
                        if let Some(c) = highest(legal.iter().copied().filter(|&c| suit(c) == SPADES && rank(c) < rank(QUEEN))) {
                            return self.w("lead:queen_hunt", c);
                        }
                    }
                }
            }
        }

        if self.mellem() {
            if let Some(void_plan) = self.void_plan_lead(known) {
                return self.w("lead:void_plan", void_plan);
            }
            if self.on(Rule::QueenChase) && known.queen_out() && ![QUEEN, KING_OF_SPADES, ACE_OF_SPADES].iter().any(|&c| known.in_hand(c)) {
                // Press with the highest spade under Q♠, keep the low ones (Anders, 2026-10-25).
                if let Some(spade) = highest(legal.iter().copied().filter(|&c| suit(c) == SPADES && rank(c) < rank(QUEEN))) {
                    return self.w("lead:queen_chase", spade);
                }
            }
        }

        if self.svaer() && self.on(Rule::LeadCost) {
            return self.w("lead:cost", self.cost_lead(known));
        }
        self.w("lead:low", self.let_lead(known))
    }

    /// Svær: the lead with the fewest expected penalty points (chance to
    /// win the stik × what lands in it), the lower card on a tie. A card
    /// that loses for sure costs nothing, so exit cards come first.
    fn cost_lead(&self, known: &Knowledge) -> Card {
        let legal = known.legal;
        let mut safe: Vec<Card> = legal
            .iter()
            .copied()
            .filter(|&c| !self.dangerous(c, known))
            .collect();
        if safe.is_empty() {
            safe = legal.to_vec();
        }
        let mut best = safe[0];
        let mut best_key = (known.lead_cost(best), rank(best));
        for &c in &safe[1..] {
            let key = (known.lead_cost(c), rank(c));
            if key.0 < best_key.0 || (key.0 == best_key.0 && key.1 < best_key.1) {
                best = c;
                best_key = key;
            }
        }
        best
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
        let c = shortest.and_then(|cards| highest(cards.iter().copied()))?;
        // Svær with J♦ −10 counted doesn't run J♦ while it can be lost.
        if c == JACK_OF_DIAMONDS && known.jack_count() && !known.top(c) {
            return None;
        }
        Some(c)
    }

    // ── Following suit ──────────────────────────────────────────────────

    fn follow(&self, known: &Knowledge) -> Card {
        let legal = known.legal;
        let winning = known.winning_card();
        let winners: Vec<Card> = legal.iter().copied().filter(|&c| rank(c) > rank(winning)).collect();
        let losers = minus(legal, &winners);

        if self.svaer() && self.shooting_moon(known) && !winners.is_empty() {
            return self.w("follow:moon", highest(legal.iter().copied()).unwrap());
        }

        if let Some(blocker) = self.block_moon(known, &winners) {
            return self.w("follow:block_moon", blocker);
        }

        if known.jack_count() {
            if let Some(c) = self.count_jack(known, &winners) {
                return self.w("follow:count_jack", c);
            }
        } else if let Some(jack) = self.take_jack(known, &winners) {
            return self.w("follow:jack", jack);
        }

        if self.mellem() && known.led_suit == Some(DIAMONDS) && known.jack_rule() && !losers.is_empty() && self.jack_out(known) {
            return self.w("follow:jack_low", lowest(losers.iter().copied()).unwrap());
        }

        if self.mellem() && self.on(Rule::Shed) && !winners.is_empty() && self.clean_and_safe(known) {
            let keeper = known.jack_keeper();
            let shed = highest(winners.iter().copied().filter(|&c| !(c == QUEEN || (c == JACK_OF_DIAMONDS && known.jack_rule()) || Some(c) == keeper)));
            if let Some(shed) = shed {
                return self.w("follow:shed", shed);
            }
        }

        if !losers.is_empty() {
            return self.w(
                "follow:duck",
                highest(losers.iter().copied().filter(|&c| !self.avoid_jack(c, known))).or_else(|| highest(losers.iter().copied())).unwrap(),
            );
        }

        let mut others = minus(legal, &[QUEEN]);
        if others.is_empty() {
            others = legal.to_vec();
        }
        if known.last_to_play() {
            self.w("follow:last_high", highest(others).unwrap())
        } else {
            self.w("follow:low_winner", lowest(others).unwrap())
        }
    }

    fn clean_and_safe(&self, known: &Knowledge) -> bool {
        if known.trick_points() > 0 {
            return false;
        }
        if known.last_to_play() {
            return true;
        }
        if self.svaer()
            && self.on(Rule::SafeShed)
            && (known.led_suit != Some(SPADES) || !known.queen_out())
            && known.dump_risk(known.led_suit.unwrap(), &known.seats_after_me()) < self.p.safe_shed
        {
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

    /// Svær, J♦ −10 counted: a diamond stik is worth its points plus what
    /// may still be dropped on it, less 10 for J♦.
    /// - J♦ in the stik: take it while that nets less than 0; the lowest
    ///   winning diamond when last, else the highest (likelier to hold).
    /// - J♦ in hand: play it when it wins for sure, on the same terms.
    fn count_jack(&self, known: &Knowledge, winners: &[Card]) -> Option<Card> {
        if known.led_suit != Some(DIAMONDS) || winners.is_empty() {
            return None;
        }
        let in_trick = known.trick_has(JACK_OF_DIAMONDS);
        let sure_jack = winners.contains(&JACK_OF_DIAMONDS) && (known.last_to_play() || known.top(JACK_OF_DIAMONDS));
        if !in_trick && !sure_jack {
            return None;
        }
        let points = known.trick_points() as f64 + if known.last_to_play() { 0.0 } else { known.dump_risk(DIAMONDS, &known.seats_after_me()) };
        if points >= JACK_POINTS {
            return None;
        }
        if sure_jack {
            Some(JACK_OF_DIAMONDS)
        } else if known.last_to_play() {
            lowest(winners.iter().copied())
        } else {
            highest(winners.iter().copied())
        }
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
            return self.w("discard:moon", lowest(legal.iter().copied().filter(|&c| !is_penalty(c))).or_else(|| lowest(legal.iter().copied())).unwrap());
        }

        let winner = known.winning_play().seat;
        if !self.feed(known, winner) {
            if let Some(c) = highest(legal.iter().copied().filter(|&c| !is_penalty(c))) {
                return self.w("discard:no_feed", c);
            }
        }

        if legal.contains(&QUEEN) {
            return self.w("discard:queen", QUEEN);
        }

        let hearts: Vec<Card> = legal.iter().copied().filter(|&c| is_heart(c)).collect();
        if !hearts.is_empty() && !self.mellem() {
            return self.w("discard:heart", highest(hearts).unwrap());
        }
        if !self.mellem() {
            return self.w("discard:high", highest(legal.iter().copied()).unwrap());
        }

        let high_spades = and(legal, &HIGH_SPADES);
        if !high_spades.is_empty() && known.queen_out() {
            return self.w("discard:high_spade", highest(high_spades).unwrap());
        }

        if self.svaer() && self.on(Rule::Liability) {
            return self.w("discard:liability", self.liability_discard(known));
        }

        if !hearts.is_empty() {
            return self.w("discard:heart", highest(hearts).unwrap());
        }

        self.w("discard:short_suit", self.shed_from_short_suit(known))
    }

    /// Svær: throw off the card most likely to win a stik later (its chance
    /// to win when led), hearts first, short suits first, the higher
    /// card on a tie.
    fn liability_discard(&self, known: &Knowledge) -> Card {
        let key = |c: Card| {
            let heart = if is_heart(c) { self.p.heart_liability } else { 0.0 };
            (known.win_chance(c) + heart - self.p.short_liability * suit_length(known.hand, suit(c)) as f64, rank(c))
        };
        let mut candidates = self.discard_candidates(known);
        // J♦ −10 counted: the highest diamond above J♦ is kept to capture it.
        if let Some(keeper) = known.jack_keeper() {
            if candidates.len() > 1 {
                candidates.retain(|&c| c != keeper);
            }
        }
        let mut best = candidates[0];
        let mut best_key = key(best);
        for &c in &candidates[1..] {
            let k = key(c);
            if k.0 > best_key.0 || (k.0 == best_key.0 && k.1 > best_key.1) {
                best = c;
                best_key = k;
            }
        }
        best
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

    /// Under a moon threat, keep the two highest cards for the last stik
    /// (spec §5); with J♦ −10 on, never throw J♦ to another seat.
    fn discard_candidates(&self, known: &Knowledge) -> Vec<Card> {
        let legal = known.legal;
        let keep: Vec<Card> = if known.moon_threat().is_some() { highest_first(legal).into_iter().take(2).collect() } else { vec![] };
        let mut candidates = minus(legal, &keep);
        if candidates.is_empty() {
            candidates = legal.to_vec();
        }
        if known.jack_rule() && candidates.len() > 1 {
            candidates.retain(|&c| c != JACK_OF_DIAMONDS);
        }
        candidates
    }

    fn shed_from_short_suit(&self, known: &Knowledge) -> Card {
        let candidates = self.discard_candidates(known);
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
        c == QUEEN || (HIGH_SPADES.contains(&c) && known.queen_out()) || (c == JACK_OF_DIAMONDS && known.jack_rule() && !known.top(c))
    }
}
