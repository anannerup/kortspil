//! Mirrors the engine in app/models/hjerterfri: Rules, PassDirection,
//! LegalMoves, Trick, Round and Round#view_for. Unlike the Ruby Round it
//! is mutable: a lab only plays forward.

use crate::card::*;

pub const SEAT_COUNT: usize = 4;
pub const HAND_SIZE: usize = 13;
pub const TRICK_COUNT: usize = 13;
pub const MOON: i32 = 26;
pub const JACK_OF_DIAMONDS_POINTS: i32 = -10;

#[derive(Clone, Copy, Debug)]
pub struct Rules {
    pub end_score: i32,
    pub queen_breaks_hearts: bool,
    pub jack_of_diamonds_minus_ten: bool,
    pub shooters_choice: bool,
}

impl Rules {
    pub fn standard() -> Self {
        Rules { end_score: 100, queen_breaks_hearts: false, jack_of_diamonds_minus_ten: false, shooters_choice: false }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PassDirection {
    Left,
    Right,
    Across,
    None,
}

impl PassDirection {
    /// Runde 1 left, 2 right, 3 across, 4 none, then the pattern repeats.
    pub fn for_runde(number: usize) -> Self {
        [PassDirection::Left, PassDirection::Right, PassDirection::Across, PassDirection::None][(number - 1) % 4]
    }
    pub fn offset(self) -> usize {
        match self {
            PassDirection::Left => 1,
            PassDirection::Right => SEAT_COUNT - 1,
            PassDirection::Across => 2,
            PassDirection::None => 0,
        }
    }
    pub fn receiver(seat: usize, direction: PassDirection) -> usize {
        (seat + direction.offset()) % SEAT_COUNT
    }
    pub fn giver(seat: usize, direction: PassDirection) -> usize {
        (seat + SEAT_COUNT - direction.offset()) % SEAT_COUNT
    }
    pub fn parse(s: &str) -> Self {
        match s {
            "left" => PassDirection::Left,
            "right" => PassDirection::Right,
            "across" => PassDirection::Across,
            _ => PassDirection::None,
        }
    }
}

/// One play in a stik: who played which card.
#[derive(Clone, Copy, Debug)]
pub struct Play {
    pub seat: usize,
    pub card: Card,
}

#[derive(Clone, Debug)]
pub struct DoneTrick {
    pub plays: Vec<Play>,
    pub winner: usize,
}

/// What the bot reads from Round#view_for(seat).
#[derive(Clone, Debug)]
pub struct View {
    pub seat: usize,
    pub hand: Vec<Card>,
    pub legal: Vec<Card>,
    pub trick: Vec<Play>,
    pub tricks: Vec<DoneTrick>,
    pub rules: Rules,
    pub hearts_broken: bool,
    pub pass_direction: PassDirection,
    pub own_pass: Vec<Card>,
    /// Round#received_cards: the cards passed to the seat (empty until every pass is in).
    pub received: Vec<Card>,
    /// Cards held per seat (Ruby gives only the others; a missing seat is 0).
    pub card_counts: [usize; SEAT_COUNT],
}

/// LegalMoves#cards: the restrictions in order, each keeping only the cards
/// it permits, never emptying the hand.
pub fn legal_moves(hand: &[Card], trick: &[Card], first_trick: bool, hearts_broken: bool) -> Vec<Card> {
    let leading = trick.is_empty();
    let mut allowed: Vec<Card> = hand.to_vec();
    let mut narrow = |permits: &dyn Fn(Card) -> bool| {
        let kept: Vec<Card> = allowed.iter().copied().filter(|&c| permits(c)).collect();
        if !kept.is_empty() {
            allowed = kept;
        }
    };
    if leading && first_trick {
        narrow(&|c| c == TWO_OF_CLUBS);
    }
    if !leading {
        let led = suit(trick[0]);
        narrow(&|c| suit(c) == led);
    }
    if first_trick {
        narrow(&|c| !is_penalty(c));
    }
    if leading && !hearts_broken {
        narrow(&|c| !is_heart(c));
    }
    allowed
}

/// Trick#winner: the highest card of the led suit.
pub fn trick_winner(leader: usize, cards: &[Card]) -> usize {
    let led = suit(cards[0]);
    let mut best = 0;
    for (i, &c) in cards.iter().enumerate() {
        if suit(c) == led && rank(c) > rank(cards[best]) {
            best = i;
        }
    }
    (leader + best) % SEAT_COUNT
}

#[derive(Clone)]
pub struct Round {
    pub rules: Rules,
    pub pass_direction: PassDirection,
    pub dealt: [Vec<Card>; SEAT_COUNT],
    pub passes: [Option<[Card; 3]>; SEAT_COUNT],
    pub hands: [Vec<Card>; SEAT_COUNT],
    pub tricks: Vec<DoneTrick>,
    pub leader: usize,
    pub trick: Vec<Card>,
    pub moon_choice: Option<bool>, // Some(true) = add_to_others
    pub plays: Vec<Card>,
}

impl Round {
    pub fn new(rules: Rules, dealt: [Vec<Card>; SEAT_COUNT], pass_direction: PassDirection) -> Self {
        let mut round = Round {
            rules,
            pass_direction,
            hands: dealt.clone(),
            dealt,
            passes: [None; SEAT_COUNT],
            tricks: Vec::new(),
            leader: 0,
            trick: Vec::new(),
            moon_choice: None,
            plays: Vec::new(),
        };
        round.set_leader();
        round
    }

    fn set_leader(&mut self) {
        self.leader = (0..SEAT_COUNT).find(|&s| self.hands[s].contains(&TWO_OF_CLUBS)).unwrap();
    }

    pub fn passing(&self) -> bool {
        self.pass_direction != PassDirection::None && self.passes.iter().any(|p| p.is_none())
    }

    pub fn pass(&mut self, seat: usize, cards: [Card; 3]) -> Result<(), String> {
        if !self.passing() || self.passes[seat].is_some() {
            return Err("not_passing".into());
        }
        if cards[0] == cards[1] || cards[0] == cards[2] || cards[1] == cards[2] {
            return Err("duplicate_cards".into());
        }
        if !cards.iter().all(|c| self.dealt[seat].contains(c)) {
            return Err("card_not_in_hand".into());
        }
        self.passes[seat] = Some(cards);
        if !self.passing() {
            for s in 0..SEAT_COUNT {
                let mine = self.passes[s].unwrap();
                let received = self.passes[PassDirection::giver(s, self.pass_direction)].unwrap();
                let mut hand: Vec<Card> = self.dealt[s].iter().copied().filter(|c| !mine.contains(c)).collect();
                hand.extend_from_slice(&received);
                self.hands[s] = hand;
            }
            self.set_leader();
        }
        Ok(())
    }

    pub fn all_tricks_played(&self) -> bool {
        self.tricks.len() == TRICK_COUNT
    }

    pub fn choosing_moon(&self) -> bool {
        self.moon_choice.is_none() && self.rules.shooters_choice && self.moon_shooter().is_some()
    }

    pub fn complete(&self) -> bool {
        self.all_tricks_played() && !self.choosing_moon()
    }

    pub fn to_act(&self) -> usize {
        if self.choosing_moon() {
            return self.moon_shooter().unwrap();
        }
        (self.leader + self.trick.len()) % SEAT_COUNT
    }

    fn played_cards(&self) -> impl Iterator<Item = Card> + '_ {
        self.tricks.iter().flat_map(|t| t.plays.iter().map(|p| p.card)).chain(self.trick.iter().copied())
    }

    pub fn hearts_broken(&self) -> bool {
        let qbh = self.rules.queen_breaks_hearts;
        self.played_cards().any(|c| is_heart(c) || (qbh && c == QUEEN))
    }

    pub fn legal_moves(&self, seat: usize) -> Vec<Card> {
        if self.passing() || self.all_tricks_played() || seat != self.to_act() {
            return Vec::new();
        }
        let mut cards = legal_moves(&self.hands[seat], &self.trick, self.tricks.is_empty(), self.hearts_broken());
        in_display_order(&mut cards);
        cards
    }

    pub fn play(&mut self, seat: usize, card: Card) -> Result<(), String> {
        if self.passing() {
            return Err("passing_not_complete".into());
        }
        if self.all_tricks_played() {
            return Err("round_complete".into());
        }
        if seat != self.to_act() {
            return Err("not_your_turn".into());
        }
        if !self.legal_moves(seat).contains(&card) {
            return Err(format!("illegal play {}", to_s(card)));
        }
        self.hands[seat].retain(|&c| c != card);
        self.trick.push(card);
        self.plays.push(card);
        if self.trick.len() == SEAT_COUNT {
            let winner = trick_winner(self.leader, &self.trick);
            let plays = self.trick.iter().enumerate().map(|(i, &c)| Play { seat: (self.leader + i) % SEAT_COUNT, card: c }).collect();
            self.tricks.push(DoneTrick { plays, winner });
            self.trick.clear();
            self.leader = winner;
        }
        Ok(())
    }

    pub fn choose_moon(&mut self, add_to_others: bool) {
        self.moon_choice = Some(add_to_others);
    }

    fn penalty_points(&self) -> [i32; SEAT_COUNT] {
        let mut points = [0; SEAT_COUNT];
        for t in &self.tricks {
            points[t.winner] += t.plays.iter().map(|p| crate::card::points(p.card)).sum::<i32>();
        }
        points
    }

    pub fn moon_shooter(&self) -> Option<usize> {
        if !self.all_tricks_played() {
            return None;
        }
        self.penalty_points().iter().position(|&p| p == MOON)
    }

    fn jack_of_diamonds_taker(&self) -> Option<usize> {
        if !self.all_tricks_played() || !self.rules.jack_of_diamonds_minus_ten {
            return None;
        }
        self.tricks.iter().find(|t| t.plays.iter().any(|p| p.card == JACK_OF_DIAMONDS)).map(|t| t.winner)
    }

    /// Round#points: after the moon and J♦.
    pub fn points(&self) -> [i32; SEAT_COUNT] {
        let shooter = self.moon_shooter();
        let mut scored = match shooter {
            Some(s) => {
                let mut p = [0; SEAT_COUNT];
                for seat in 0..SEAT_COUNT {
                    p[seat] = if self.moon_choice == Some(false) {
                        if seat == s { -MOON } else { 0 }
                    } else if seat == s {
                        0
                    } else {
                        MOON
                    };
                }
                p
            }
            None => self.penalty_points(),
        };
        if let Some(jack) = self.jack_of_diamonds_taker() {
            if Some(jack) != shooter {
                scored[jack] += JACK_OF_DIAMONDS_POINTS;
            }
        }
        scored
    }

    pub fn view_for(&self, seat: usize) -> View {
        let mut hand = self.hands[seat].clone();
        in_display_order(&mut hand);
        let mut own_pass: Vec<Card> = self.passes[seat].map(|p| p.to_vec()).unwrap_or_default();
        in_display_order(&mut own_pass);
        let mut received: Vec<Card> = if self.pass_direction == PassDirection::None || self.passes.iter().any(|p| p.is_none()) {
            Vec::new()
        } else {
            self.passes[PassDirection::giver(seat, self.pass_direction)].unwrap().to_vec()
        };
        in_display_order(&mut received);
        let mut card_counts = [0; SEAT_COUNT];
        for s in 0..SEAT_COUNT {
            if s != seat {
                card_counts[s] = self.hands[s].len();
            }
        }
        View {
            seat,
            hand,
            legal: self.legal_moves(seat),
            trick: self.trick.iter().enumerate().map(|(i, &c)| Play { seat: (self.leader + i) % SEAT_COUNT, card: c }).collect(),
            tricks: self.tricks.clone(),
            rules: self.rules,
            hearts_broken: self.hearts_broken(),
            pass_direction: self.pass_direction,
            own_pass,
            received,
            card_counts,
        }
    }
}
