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

/// Rules that can be switched off for one level (`--off svaer:moon`).
#[derive(Clone, Copy, Debug)]
pub enum Rule {
    Moon,          // Svær: shoot the moon (play and moon pass)
    QueenHunt,     // Svær: lead spades at Q♠'s known seat
    Scores,        // Svær: read totals and the end score
    Counting,      // Svær: exact void odds and unknown-card weights (off: Mellem's rough sense)
    SpadeEvidence, // Svær: following spades under A♠/K♠ without Q♠
    Evidence,      // Mellem+: throwing off another card instead of Q♠
    VoidPlan,      // Mellem+: run a short minor suit early
    QueenChase,    // Mellem+: press with the highest spade under Q♠ while it is out
    Shed,          // Mellem+: take a clean stik with the highest card
    Risk,          // every level: avoid leading a high card when risky
    BlockMoon,     // Mellem+: stop the moon
    Jack,          // Mellem+: J♦ −10 rules
    Feed,          // Mellem+/Svær: whom to give penalty cards
    LeadCost,      // Svær: lead the card with the fewest expected penalty points
    SafeShed,      // Svær: take a stik with the highest card when it is safe
    Liability,     // Svær: throw off the card likeliest to win a stik later
    LowCover,      // Svær: pass high cards from suits with the fewest low cards
    Received,      // Mellem+: the received cards tell where the giver is void
    PassedVoids,   // Svær: other seats are likelier void after a pass
}

pub const RULE_NAMES: &[(&str, Rule)] = &[
    ("moon", Rule::Moon),
    ("queen_hunt", Rule::QueenHunt),
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
    ("lead_cost", Rule::LeadCost),
    ("safe_shed", Rule::SafeShed),
    ("liability", Rule::Liability),
    ("low_cover", Rule::LowCover),
    ("received", Rule::Received),
    ("passed_voids", Rule::PassedVoids),
];

#[derive(Clone, Debug)]
pub struct Params {
    /// Knowledge::RISKY: expected points from which a high card counts as risky.
    pub risky: f64,
    /// Knowledge::MOON_THREAT
    pub moon_threat: i32,
    /// Bot::HIGH: rank index from which a card is "high" (8 = ten).
    pub high: u8,
    /// Bot#void_plan_lead: only while the hand has at least this many cards.
    pub void_plan_hand: usize,
    /// Knowledge#queen_evidence factors.
    pub discard_evidence: f64,
    pub spade_evidence: f64,
    /// Svær: chance the giver is void in a suit (not hearts) at the start of
    /// play, by how many cards of it it passed to the seat (0–3).
    pub received_void: [f64; 4],
    /// Svær: chance any other seat is void in clubs/diamonds, and in spades,
    /// at the start of play after a pass (seats pass short suits away).
    pub passed_void_minor: f64,
    pub passed_void_spades: f64,
    /// Mellem: "the giver passed me 2+ cards of a suit, so it is likely void".
    pub mellem_received_void: f64,
    /// Svær: take a stik early with the highest card when the expected
    /// dropped points from the seats after it are under this.
    pub safe_shed: f64,
    /// Svær's discard: what a heart adds to a card's chance to win, and
    /// what each card of its suit takes off (short suits go first).
    pub heart_liability: f64,
    pub short_liability: f64,
    /// Svær passes Q♠ unless it has this many other spades (Mellem: 3).
    pub svaer_queen_guards: usize,
    /// Rules switched off, one bit per Rule, per level.
    pub off: [u32; 3],
    /// Experiment knobs (--x0 .. --x9), for trying ideas before they get names.
    pub x: [f64; 10],
}

impl Default for Params {
    fn default() -> Self {
        Params {
            risky: 1.0,
            moon_threat: 17,
            high: 0,
            void_plan_hand: 10,
            discard_evidence: 0.2,
            spade_evidence: 0.4,
            received_void: [0.014, 0.096, 0.33, 0.40],
            passed_void_minor: 0.16,
            passed_void_spades: 0.026,
            mellem_received_void: 0.5,
            safe_shed: 0.3,
            heart_liability: 0.6,
            short_liability: 0.2,
            svaer_queen_guards: 5,
            off: [0; 3],
            x: [0.0; 10],
        }
    }
}

impl Params {
    /// Sets a number by name (`--name value`, dashes or underscores).
    pub fn set(&mut self, name: &str, v: f64) -> bool {
        match name.replace('-', "_").as_str() {
            "risky" => self.risky = v,
            "moon_threat" => self.moon_threat = v as i32,
            "high" => self.high = v as u8,
            "void_plan_hand" => self.void_plan_hand = v as usize,
            "discard_evidence" => self.discard_evidence = v,
            "spade_evidence" => self.spade_evidence = v,
            "svaer_queen_guards" => self.svaer_queen_guards = v as usize,
            "safe_shed" => self.safe_shed = v,
            "heart_liability" => self.heart_liability = v,
            "short_liability" => self.short_liability = v,
            "received_void0" => self.received_void[0] = v,
            "received_void1" => self.received_void[1] = v,
            "received_void2" => self.received_void[2] = v,
            "received_void3" => self.received_void[3] = v,
            "passed_void_minor" => self.passed_void_minor = v,
            "passed_void_spades" => self.passed_void_spades = v,
            "mellem_received_void" => self.mellem_received_void = v,
            x if x.starts_with('x') && x[1..].parse::<usize>().is_ok() => self.x[x[1..].parse::<usize>().unwrap()] = v,
            _ => return false,
        }
        true
    }

    pub fn on(&self, level: Level, rule: Rule) -> bool {
        self.off[level.index()] & (1 << rule as u32) == 0
    }

    /// "svaer:moon,svaer:counting" or "all:risk".
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
