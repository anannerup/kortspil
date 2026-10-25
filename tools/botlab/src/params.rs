//! The [valgt] numbers (docs/bots/hjerterfri-strategy.md) and switches to
//! turn single rules off per level, for tuning and ablation. The defaults
//! are what Ruby (app/models/hjerterfri/bot.rb, bot/knowledge.rb) uses.

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Level {
    Let,
    Mellem,
    Svaer,
}

pub const LEVELS: [Level; 3] = [Level::Let, Level::Mellem, Level::Svaer];

impl Level {
    pub fn parse(s: &str) -> Option<Level> {
        match s {
            "let" => Some(Level::Let),
            "mellem" => Some(Level::Mellem),
            "svaer" => Some(Level::Svaer),
            _ => None,
        }
    }
    pub fn name(self) -> &'static str {
        match self {
            Level::Let => "let",
            Level::Mellem => "mellem",
            Level::Svaer => "svaer",
        }
    }
    pub fn index(self) -> usize {
        self as usize
    }
}

/// Rules that can be switched off for one level (`--off svaer:late`).
#[derive(Clone, Copy, Debug)]
pub enum Rule {
    Moon,          // Svær: shoot the moon (play and moon pass)
    Late,          // Svær: exit cards late in the runde
    SafeHigh,      // Svær: cash a suit's top card
    QueenHunt,     // Svær: lead spades at Q♠'s known seat
    TwoLowSuits,   // Svær: keep low cards in two suits when discarding
    Scores,        // Svær: read totals and the end score
    Counting,      // Svær: exact void odds and unknown-card weights (off: Mellem's rough sense)
    SpadeEvidence, // Svær: following spades under A♠/K♠ without Q♠
    Evidence,      // Mellem+: throwing off another card instead of Q♠
    VoidPlan,      // Mellem+: run a short minor suit early
    QueenChase,    // Mellem+: lead low spades while Q♠ is out
    Shed,          // Mellem+: take a clean stik with the highest card
    Risk,          // every level: avoid leading a high card when risky
    BlockMoon,     // Mellem+: stop the moon
    Jack,          // Mellem+: J♦ −10 rules
    Feed,          // Mellem+/Svær: whom to give penalty cards
}

pub const RULE_NAMES: &[(&str, Rule)] = &[
    ("moon", Rule::Moon),
    ("late", Rule::Late),
    ("safe_high", Rule::SafeHigh),
    ("queen_hunt", Rule::QueenHunt),
    ("two_low_suits", Rule::TwoLowSuits),
    ("scores", Rule::Scores),
    ("counting", Rule::Counting),
    ("spade_evidence", Rule::SpadeEvidence),
    ("evidence", Rule::Evidence),
    ("void_plan", Rule::VoidPlan),
    ("queen_chase", Rule::QueenChase),
    ("shed", Rule::Shed),
    ("risk", Rule::Risk),
    ("block_moon", Rule::BlockMoon),
    ("jack", Rule::Jack),
    ("feed", Rule::Feed),
];

#[derive(Clone, Debug)]
pub struct Params {
    /// Knowledge::RISKY: expected points from which a high card counts as risky.
    pub risky: f64,
    /// Knowledge::SAFE: expected points under which a stik counts as safe.
    pub safe: f64,
    /// Knowledge::MOON_THREAT
    pub moon_threat: i32,
    /// Knowledge::LATE
    pub late: usize,
    /// Bot::HIGH: rank index from which a card is "high" (8 = ten).
    pub high: u8,
    /// Bot#void_plan_lead: only while the hand has at least this many cards.
    pub void_plan_hand: usize,
    /// Bot#safe_high_lead: only once the hand has at most this many cards.
    pub safe_high_hand: usize,
    /// Knowledge#queen_evidence factors.
    pub discard_evidence: f64,
    pub spade_evidence: f64,
    /// Rules switched off, one bit per Rule, per level.
    pub off: [u32; 3],
}

impl Default for Params {
    fn default() -> Self {
        Params {
            risky: 2.0,
            safe: 0.1,
            moon_threat: 14,
            late: 4,
            high: 8,
            void_plan_hand: 10,
            safe_high_hand: 11,
            discard_evidence: 0.2,
            spade_evidence: 0.4,
            off: [0; 3],
        }
    }
}

impl Params {
    pub fn on(&self, level: Level, rule: Rule) -> bool {
        self.off[level.index()] & (1 << rule as u32) == 0
    }

    /// "svaer:late,svaer:moon" or "all:risk".
    pub fn switch_off(&mut self, list: &str) -> Result<(), String> {
        for item in list.split(',').filter(|s| !s.is_empty()) {
            let (level, rule) = item.split_once(':').ok_or(format!("expected level:rule, got {item}"))?;
            let rule = RULE_NAMES.iter().find(|(n, _)| *n == rule).ok_or(format!("unknown rule {rule}"))?.1;
            let levels: Vec<Level> = if level == "all" { LEVELS.to_vec() } else { vec![Level::parse(level).ok_or(format!("unknown level {level}"))?] };
            for l in levels {
                self.off[l.index()] |= 1 << rule as u32;
            }
        }
        Ok(())
    }
}
