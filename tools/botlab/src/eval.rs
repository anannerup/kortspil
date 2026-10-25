//! `botlab eval`: a level's own strength, apart from its opponents and the
//! cards (spec §8, README "Evaluation").
//!
//! One seat of level X plays against a fixed field of three bots of level
//! R. The same spil (same seed, so the same deals runde by runde and the
//! same variation seeds per seat) is also played with R in X's seat: the
//! baseline. X's result is compared with R's result in the same seat on
//! the same cards, so card luck and the field cancel out of the
//! difference. X takes every seat in turn (spil i puts X in seat i % 4).
//!
//! Reported per field and level, each with a 95 % confidence interval:
//! - win rate: share of spil X ends lowest (ties split); 25 % is the
//!   field's own level, since the baseline is four equal bots;
//! - place: average finishing place 1–4 (ties share the places);
//! - Δ point pr. runde: X's points per runde minus R's in the same seat on
//!   the same deals (negative is better), paired per spil.
//! Plus a rating: Elo-style points from the win rate against the field,
//! where 25 % is 0 (see `rating`).

use crate::params::{Level, Params, LEVELS};
use crate::round::{Rules, SEAT_COUNT};
use crate::bot::Bot;
use crate::rng::Rng;
use crate::round::{PassDirection, Round};
use crate::tournament::{deal, play_deal, play_spil, SpilResult};

#[derive(Default, Clone)]
struct Stat {
    values: Vec<f64>,
}

impl Stat {
    fn push(&mut self, v: f64) {
        self.values.push(v);
    }
    fn extend(&mut self, other: &Stat) {
        self.values.extend_from_slice(&other.values);
    }
    /// Mean and the half-width of its 95 % confidence interval.
    fn mean_ci(&self) -> (f64, f64) {
        let n = self.values.len() as f64;
        let mean = self.values.iter().sum::<f64>() / n;
        let var = self.values.iter().map(|v| (v - mean).powi(2)).sum::<f64>() / (n - 1.0).max(1.0);
        (mean, 1.96 * (var / n).sqrt())
    }
}

#[derive(Default, Clone)]
struct Cell {
    win: Stat,
    place: Stat,
    per_runde: Stat,
    delta: Stat,
    win_delta: Stat,
}

/// Seat `seat`'s share of the win (1/k when k seats tie lowest) and its
/// place (1 + seats strictly lower + half the other seats tied with it).
fn win_and_place(result: &SpilResult, seat: usize) -> (f64, f64) {
    let mine = result.totals[seat];
    let win = if result.winners.contains(&seat) { 1.0 / result.winners.len() as f64 } else { 0.0 };
    let lower = result.totals.iter().filter(|&&t| t < mine).count() as f64;
    let tied = result.totals.iter().filter(|&&t| t == mine).count() as f64 - 1.0;
    (win, 1.0 + lower + tied / 2.0)
}

/// Elo-style rating from a win rate p against three equal opponents: the
/// rating difference d to each of them at which a four-way Bradley–Terry
/// model gives p, i.e. p = s / (s + 3) with s = 10^(d/400).
pub fn rating(p: f64) -> f64 {
    let p = p.clamp(1e-6, 1.0 - 1e-6);
    400.0 * (3.0 * p / (1.0 - p)).log10()
}

pub fn run(spil: usize, seed: u64, threads: usize, rules: Rules, p: &Params, fields: &[Level], levels: &[Level]) {
    let started = std::time::Instant::now();
    for &field in fields {
        let cells: Vec<Vec<Cell>> = std::thread::scope(|scope| {
            let handles: Vec<_> = (0..threads)
                .map(|t| {
                    scope.spawn(move || {
                        let mut cells = vec![Cell::default(); levels.len()];
                        let mut index = t;
                        while index < spil {
                            let spil_seed = seed * 100_000 + index as u64;
                            let seat = index % SEAT_COUNT;
                            let baseline = play_spil([field; SEAT_COUNT], spil_seed, rules, p);
                            let base_per = baseline.totals[seat] as f64 / baseline.runder as f64;
                            let (base_win, _) = win_and_place(&baseline, seat);
                            for (i, &level) in levels.iter().enumerate() {
                                let result = if level == field {
                                    SpilResult { totals: baseline.totals, runder: baseline.runder, winners: baseline.winners.clone() }
                                } else {
                                    let mut seats = [field; SEAT_COUNT];
                                    seats[seat] = level;
                                    play_spil(seats, spil_seed, rules, p)
                                };
                                let (win, place) = win_and_place(&result, seat);
                                let per = result.totals[seat] as f64 / result.runder as f64;
                                let cell = &mut cells[i];
                                cell.win.push(win);
                                cell.place.push(place);
                                cell.per_runde.push(per);
                                cell.delta.push(per - base_per);
                                cell.win_delta.push(win - base_win);
                            }
                            index += threads;
                        }
                        cells
                    })
                })
                .collect();
            handles.into_iter().map(|h| h.join().unwrap()).collect()
        });
        let mut total = vec![Cell::default(); levels.len()];
        for part in &cells {
            for (i, cell) in part.iter().enumerate() {
                total[i].win.extend(&cell.win);
                total[i].place.extend(&cell.place);
                total[i].per_runde.extend(&cell.per_runde);
                total[i].delta.extend(&cell.delta);
                total[i].win_delta.extend(&cell.win_delta);
            }
        }
        println!("field 3 × {} ({} spil per level, seed {}):", field.name(), spil, seed);
        println!("  {:<7} {:>15} {:>16} {:>13} {:>18} {:>7}", "level", "win %", "vs field's seat", "place", "Δ point pr. runde", "rating");
        for (i, &level) in levels.iter().enumerate() {
            let (w, wci) = total[i].win.mean_ci();
            let (wd, wdci) = total[i].win_delta.mean_ci();
            let (pl, plci) = total[i].place.mean_ci();
            let (d, dci) = total[i].delta.mean_ci();
            println!(
                "  {:<7} {:6.1} ± {:4.1} {:+7.1} ± {:4.1} {:5.2} ± {:4.2} {:+8.2} ± {:4.2} {:+7.0}",
                level.name(),
                100.0 * w,
                100.0 * wci,
                100.0 * wd,
                100.0 * wdci,
                pl,
                plci,
                d,
                dci,
                rating(w)
            );
        }
    }
    println!("({:.1} s)", started.elapsed().as_secs_f64());
}

pub fn parse_levels(list: &str) -> Option<Vec<Level>> {
    if list == "all" {
        return Some(LEVELS.to_vec());
    }
    list.split(',').map(Level::parse).collect()
}

// ── Duplicate play: the same hand from the same seat ───────────────────

/// The deal, pass direction and totals for duplicate deal `index`.
fn duplicate_deal(seed: u64, index: usize) -> ([Vec<crate::card::Card>; SEAT_COUNT], PassDirection) {
    let mut shuffler = Rng::new(seed * 1_000_003 + index as u64);
    (deal(&mut shuffler), PassDirection::for_runde(index % 4 + 1))
}

/// One runde of duplicate deal `index` with `level` in `seat` and the field
/// elsewhere; the variation seeds depend only on the deal and the seat.
pub fn duplicate_round(seed: u64, index: usize, seat: usize, level: Level, field: Level, rules: Rules, p: &Params) -> Round {
    duplicate_round_with(seed, index, seat, level, p, field, p, rules)
}

/// As duplicate_round, the seat's bot with its own numbers `mine`.
#[allow(clippy::too_many_arguments)]
pub fn duplicate_round_with(seed: u64, index: usize, seat: usize, level: Level, mine: &Params, field: Level, p: &Params, rules: Rules) -> Round {
    let (dealt, direction) = duplicate_deal(seed, index);
    let mut bots: Vec<Bot> = (0..SEAT_COUNT)
        .map(|s| {
            let (l, params) = if s == seat { (level, mine) } else { (field, p) };
            Bot::new(l, params, Some(Rng::new((seed * 1_000_003 + index as u64) * 4 + s as u64)))
        })
        .collect();
    play_deal(&mut bots, dealt, rules, direction, &[0; SEAT_COUNT])
}

fn duplicate_bots(seed: u64, index: usize, seat: usize, level: Level, field: Level, p: &Params) -> Vec<Bot<'_>> {
    (0..SEAT_COUNT)
        .map(|s| Bot::new(if s == seat { level } else { field }, p, Some(Rng::new((seed * 1_000_003 + index as u64) * 4 + s as u64))))
        .collect()
}

/// `botlab tune`: for each candidate ("name=v1,v2" tries each value; "off=level:rule"
/// switches a rule off), the level's points per runde with the candidate
/// minus with the defaults, on the same hands from the same seat against
/// the same default field. Negative is better.
pub fn tune(deals: usize, seed: u64, threads: usize, rules: Rules, p: &Params, fields: &[Level], level: Level, tries: &[String]) {
    let mut candidates: Vec<(String, Params)> = Vec::new();
    for t in tries.iter().flat_map(|t| t.split(';')) {
        let (name, values) = t.split_once('=').expect("name=values");
        for v in values.split(',') {
            let mut c = p.clone();
            if name == "off" {
                c.switch_off(v).expect("level:rule");
            } else if !c.set(name, v.parse().expect("number")) {
                panic!("unknown number {name}");
            }
            candidates.push((format!("{name}={v}"), c));
        }
    }
    for (label, c) in &candidates {
        let mut line = format!("  {:<28}", label);
        let mut all = Stat::default();
        for &field in fields {
            let parts: Vec<Vec<f64>> = std::thread::scope(|scope| {
                (0..threads)
                    .map(|t| {
                        scope.spawn(move || {
                            let mut out = Vec::new();
                            let mut index = t;
                            while index < deals {
                                for seat in 0..SEAT_COUNT {
                                    let a = duplicate_round_with(seed, index, seat, level, c, field, p, rules).points()[seat];
                                    let b = duplicate_round_with(seed, index, seat, level, p, field, p, rules).points()[seat];
                                    out.push((a - b) as f64);
                                }
                                index += threads;
                            }
                            out
                        })
                    })
                    .collect::<Vec<_>>()
                    .into_iter()
                    .map(|h| h.join().unwrap())
                    .collect()
            });
            let mut st = Stat::default();
            parts.iter().flatten().for_each(|&v| {
                st.push(v);
                all.push(v);
            });
            let (m, ci) = st.mean_ci();
            line += &format!("  {}: {:+.3} ± {:.3}", field.name(), m, ci);
        }
        let (m, ci) = all.mean_ci();
        println!("{line}  all: {:+.3} ± {:.3}", m, ci);
    }
}

/// The duplicate deal after the pass, ready to play, with its bots.
pub fn duplicate_setup(seed: u64, index: usize, seat: usize, level: Level, field: Level, rules: Rules, p: &Params) -> (Round, Vec<Bot<'_>>) {
    let (dealt, direction) = duplicate_deal(seed, index);
    let bots = duplicate_bots(seed, index, seat, level, field, p);
    let mut round = Round::new(rules, dealt, direction);
    if round.passing() {
        for s in 0..SEAT_COUNT {
            let pass = bots[s].choose_pass(&round.view_for(s).hand);
            round.pass(s, [pass[0], pass[1], pass[2]]).unwrap();
        }
    }
    (round, bots)
}

/// `botlab hands`: every deal is played once per level and seat, each level
/// holding the very same hand from the very same seat against the same
/// field. Reports points per runde per level and, per pair of levels, how
/// often the stronger one does better with the same hand.
pub fn hands(deals: usize, seed: u64, threads: usize, rules: Rules, p: &Params, field: Level, show: usize) {
    let started = std::time::Instant::now();
    // results[deal * 4 + seat][level index]
    let parts: Vec<Vec<(usize, [i32; 3])>> = std::thread::scope(|scope| {
        let handles: Vec<_> = (0..threads)
            .map(|t| {
                scope.spawn(move || {
                    let mut out = Vec::new();
                    let mut index = t;
                    while index < deals {
                        for seat in 0..SEAT_COUNT {
                            let points: [i32; 3] = std::array::from_fn(|l| duplicate_round(seed, index, seat, LEVELS[l], field, rules, p).points()[seat]);
                            out.push((index * SEAT_COUNT + seat, points));
                        }
                        index += threads;
                    }
                    out
                })
            })
            .collect();
        handles.into_iter().map(|h| h.join().unwrap()).collect()
    });
    let mut results: Vec<(usize, [i32; 3])> = parts.into_iter().flatten().collect();
    results.sort_by_key(|r| r.0);

    println!("duplicate: {} deals × 4 seats, field 3 × {}, seed {} ({:.1} s)", deals, field.name(), seed, started.elapsed().as_secs_f64());
    for l in 0..3 {
        let mut s = Stat::default();
        results.iter().for_each(|r| s.push(r.1[l] as f64));
        let (m, ci) = s.mean_ci();
        println!("  {:<7} {:5.2} ± {:4.2} point pr. runde", LEVELS[l].name(), m, ci);
    }
    println!("  same hand, same seat          better  same   worse  (loses by)  Δ point pr. runde");
    for (a, b) in [(2usize, 1usize), (1, 0), (2, 0)] {
        let n = results.len() as f64;
        let better = results.iter().filter(|r| r.1[a] < r.1[b]).count() as f64;
        let worse: Vec<f64> = results.iter().filter(|r| r.1[a] > r.1[b]).map(|r| (r.1[a] - r.1[b]) as f64).collect();
        let same = n - better - worse.len() as f64;
        let mut d = Stat::default();
        results.iter().for_each(|r| d.push((r.1[a] - r.1[b]) as f64));
        let (dm, dci) = d.mean_ci();
        let loses_by = if worse.is_empty() { 0.0 } else { worse.iter().sum::<f64>() / worse.len() as f64 };
        println!(
            "  {:<6} vs {:<6}             {:5.1} % {:5.1} % {:5.1} %  ({:5.2})    {:+.2} ± {:.2}",
            LEVELS[a].name(),
            LEVELS[b].name(),
            100.0 * better / n,
            100.0 * same / n,
            100.0 * worse.len() as f64 / n,
            loses_by,
            dm,
            dci
        );
    }
    if show > 0 {
        let mut worst = results.clone();
        worst.sort_by_key(|r| (std::cmp::Reverse(r.1[2] - r.1[1]), r.0));
        println!("  deals where svaer did worst against mellem (deal seat: svaer mellem let):");
        for r in worst.iter().take(show) {
            println!("    {} {}: {} {} {}", r.0 / SEAT_COUNT, r.0 % SEAT_COUNT, r.1[2], r.1[1], r.1[0]);
        }
    }
}

/// `botlab trace`: the runde of one duplicate deal, as each level played it.
pub fn trace(seed: u64, index: usize, seat: usize, field: Level, rules: Rules, p: &Params, levels: &[Level]) {
    let (dealt, direction) = duplicate_deal(seed, index);
    println!("deal {index}, seat {seat}, pass {:?}, field {}", direction, field.name());
    for s in 0..SEAT_COUNT {
        let mut hand = dealt[s].clone();
        crate::card::in_display_order(&mut hand);
        println!("  seat {s}: {}", hand.iter().map(|&c| crate::card::to_s(c)).collect::<Vec<_>>().join(" "));
    }
    for &level in levels {
        let round = duplicate_round(seed, index, seat, level, field, rules, p);
        println!("{} in seat {seat}: points {:?}", level.name(), round.points());
        for s in 0..SEAT_COUNT {
            if let Some(pass) = round.passes[s] {
                println!("  seat {s} passed {}", pass.iter().map(|&c| crate::card::to_s(c)).collect::<Vec<_>>().join(" "));
            }
        }
        for (n, t) in round.tricks.iter().enumerate() {
            let plays: Vec<String> =
                t.plays.iter().map(|pl| format!("{}{}{}", if pl.seat == seat { "*" } else { "" }, pl.seat, crate::card::to_s(pl.card))).collect();
            println!("  {:2}: {}  -> {}", n + 1, plays.join(" "), t.winner);
        }
    }
}
