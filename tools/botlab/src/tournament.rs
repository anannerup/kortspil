//! Mirrors app/models/hjerterfri/tournament.rb: seeded spil between bots of
//! every level, rotated over the seats; average points per runde per level.

use crate::bot::Bot;
use crate::card::Card;
use crate::params::{Level, Params, LEVELS};
use crate::rng::Rng;
use crate::round::{PassDirection, Round, Rules, HAND_SIZE, SEAT_COUNT};

/// Each pattern seats one level twice; every pattern is rotated over the seats.
pub fn patterns() -> Vec<[Level; 4]> {
    let mut out = Vec::new();
    for twice in LEVELS {
        for turn in 0..SEAT_COUNT {
            let mut seats = [Level::Let, Level::Mellem, Level::Svaer, twice];
            seats.rotate_left(turn);
            out.push(seats);
        }
    }
    out
}

pub struct SpilResult {
    pub totals: [i32; SEAT_COUNT],
    pub runder: usize,
    pub winners: Vec<usize>,
}

pub fn deal(shuffler: &mut Rng) -> [Vec<Card>; SEAT_COUNT] {
    let mut deck: Vec<Card> = crate::card::deck().collect();
    shuffler.shuffle(&mut deck);
    std::array::from_fn(|seat| deck[seat * HAND_SIZE..(seat + 1) * HAND_SIZE].to_vec())
}

pub fn play_spil(levels: [Level; 4], seed: u64, rules: Rules, p: &Params) -> SpilResult {
    let mut bots: Vec<Bot> = (0..SEAT_COUNT).map(|seat| Bot::new(levels[seat], p, Some(Rng::new(seed * 4 + seat as u64)))).collect();
    let mut shuffler = Rng::new(seed);
    let mut totals = [0i32; SEAT_COUNT];
    let mut runder = 0;
    loop {
        let points = play_runde(&mut bots, &mut shuffler, rules, runder + 1, &totals);
        for seat in 0..SEAT_COUNT {
            totals[seat] += points[seat];
        }
        runder += 1;
        if *totals.iter().max().unwrap() >= rules.end_score {
            break;
        }
    }
    let min = *totals.iter().min().unwrap();
    let winners = (0..SEAT_COUNT).filter(|&s| totals[s] == min).collect();
    SpilResult { totals, runder, winners }
}

fn play_runde(bots: &mut [Bot], shuffler: &mut Rng, rules: Rules, number: usize, totals: &[i32; SEAT_COUNT]) -> [i32; SEAT_COUNT] {
    play_deal(bots, deal(shuffler), rules, PassDirection::for_runde(number), totals).points()
}

/// Plays one runde from a deal to the end and returns the finished round.
pub fn play_deal(bots: &mut [Bot], dealt: [Vec<Card>; SEAT_COUNT], rules: Rules, direction: PassDirection, totals: &[i32; SEAT_COUNT]) -> Round {
    let mut round = Round::new(rules, dealt, direction);
    if round.passing() {
        for seat in 0..SEAT_COUNT {
            let hand = round.view_for(seat).hand;
            let pass = bots[seat].choose_pass(&hand);
            round.pass(seat, [pass[0], pass[1], pass[2]]).expect("bot passed illegally");
        }
    }
    while !round.complete() {
        let seat = round.to_act();
        if round.choosing_moon() {
            let choice = bots[seat].choose_moon(seat, totals);
            round.choose_moon(choice);
        } else {
            let view = round.view_for(seat);
            let card = bots[seat].choose_play(&view, Some(*totals), Some(rules.end_score));
            round.play(seat, card).expect("bot played illegally");
        }
    }
    round
}

#[derive(Default)]
struct Tally {
    points: [i64; 3],
    seat_runder: [i64; 3],
    wins: [u64; 3],
    runder: u64,
    /// Per spil: (Svær − Mellem, Mellem − Let) in points per runde.
    diffs: Vec<(f64, f64)>,
}

pub fn run(spil: usize, seed: u64, threads: usize, rules: Rules, p: &Params) {
    let started = std::time::Instant::now();
    let patterns = patterns();
    let tallies: Vec<Tally> = std::thread::scope(|scope| {
        let handles: Vec<_> = (0..threads)
            .map(|t| {
                let patterns = &patterns;
                scope.spawn(move || {
                    let mut tally = Tally::default();
                    let mut index = t;
                    while index < spil {
                        let levels = patterns[index % patterns.len()];
                        let result = play_spil(levels, seed * 100_000 + index as u64, rules, p);
                        let mut per = [0f64; 3];
                        let mut seats = [0f64; 3];
                        for seat in 0..SEAT_COUNT {
                            let l = levels[seat].index();
                            tally.points[l] += result.totals[seat] as i64;
                            tally.seat_runder[l] += result.runder as i64;
                            per[l] += result.totals[seat] as f64;
                            seats[l] += result.runder as f64;
                        }
                        for &w in &result.winners {
                            tally.wins[levels[w].index()] += 1;
                        }
                        tally.runder += result.runder as u64;
                        let avg = |l: usize| per[l] / seats[l];
                        tally.diffs.push((avg(2) - avg(1), avg(1) - avg(0)));
                        index += threads;
                    }
                    tally
                })
            })
            .collect();
        handles.into_iter().map(|h| h.join().unwrap()).collect()
    });

    let mut total = Tally::default();
    for t in tallies {
        for l in 0..3 {
            total.points[l] += t.points[l];
            total.seat_runder[l] += t.seat_runder[l];
            total.wins[l] += t.wins[l];
        }
        total.runder += t.runder;
        total.diffs.extend(t.diffs);
    }

    println!("{} spil, {} runder ({:.1} s, {} threads)", spil, total.runder, started.elapsed().as_secs_f64(), threads);
    let mut order: Vec<usize> = (0..3).collect();
    let per = |l: usize| total.points[l] as f64 / total.seat_runder[l] as f64;
    order.sort_by(|&a, &b| per(a).partial_cmp(&per(b)).unwrap());
    for l in order {
        println!("  {:<7} {:6.2} point pr. runde   {} sejre", LEVELS[l].name(), per(l), total.wins[l]);
    }
    let stats = |values: Vec<f64>| {
        let n = values.len() as f64;
        let mean = values.iter().sum::<f64>() / n;
        let var = values.iter().map(|v| (v - mean).powi(2)).sum::<f64>() / (n - 1.0);
        (mean, (var / n).sqrt())
    };
    let (d1, se1) = stats(total.diffs.iter().map(|d| d.0).collect());
    let (d2, se2) = stats(total.diffs.iter().map(|d| d.1).collect());
    println!("  svaer - mellem {:+.2} ± {:.2} (per spil, 1 SE)", d1, se1);
    println!("  mellem - let   {:+.2} ± {:.2}", d2, se2);
}
