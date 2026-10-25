//! `botlab regret`: where a level's rules lose points (analysis only, not
//! a bot). Svær plays duplicate deals against a field; at each of its
//! choices every legal card is tried in W worlds sampled from what Svær
//! may know (its hand, the stik so far, shown voids, the cards it passed),
//! and the runde is played out by the bots themselves. The regret of a
//! choice is its average points minus the best card's. Summed per rule,
//! it shows which rules cost the most.

use crate::bot::Bot;
use crate::card::*;
use crate::eval::duplicate_setup;
use crate::params::{Level, Params};
use crate::rng::Rng;
use crate::round::{PassDirection, Round, Rules, SEAT_COUNT};
use std::collections::BTreeMap;

/// A world: Svær's own hand and everything public kept, the other hands
/// redealt from the unseen cards, respecting shown voids and the cards
/// Svær passed (still with the receiver until played).
fn sample_world(round: &Round, me: usize, rng: &mut Rng) -> Option<Round> {
    let mut void = [[false; 4]; SEAT_COUNT];
    let mut played = 0u64;
    let all: Vec<Vec<crate::round::Play>> = round
        .tricks
        .iter()
        .map(|t| t.plays.clone())
        .chain(std::iter::once(
            round.trick.iter().enumerate().map(|(i, &c)| crate::round::Play { seat: (round.leader + i) % SEAT_COUNT, card: c }).collect(),
        ))
        .collect();
    for plays in &all {
        if plays.is_empty() {
            continue;
        }
        let led = suit(plays[0].card);
        for pl in plays {
            played |= 1 << pl.card;
            if suit(pl.card) != led {
                void[pl.seat][led as usize] = true;
            }
        }
    }
    let mut hands: [Vec<Card>; SEAT_COUNT] = Default::default();
    hands[me] = round.hands[me].clone();
    let mut need: [usize; SEAT_COUNT] = std::array::from_fn(|s| round.hands[s].len());
    need[me] = 0;
    let mut pool: Vec<Card> = Vec::new();
    let receiver = PassDirection::receiver(me, round.pass_direction);
    let mine = round.passes[me];
    for c in deck() {
        if played & (1 << c) != 0 || round.hands[me].contains(&c) {
            continue;
        }
        if round.pass_direction != PassDirection::None && mine.map_or(false, |p| p.contains(&c)) {
            hands[receiver].push(c);
            need[receiver] -= 1;
        } else {
            pool.push(c);
        }
    }
    for _ in 0..50 {
        rng.shuffle(&mut pool);
        let mut h = hands.clone();
        let mut n = need;
        // Most constrained cards first: fewest seats that can hold them.
        let options = |c: Card| (0..SEAT_COUNT).filter(|&s| s != me && !void[s][suit(c) as usize]).count();
        let mut order = pool.clone();
        order.sort_by_key(|&c| options(c));
        let mut ok = true;
        for c in order {
            let seats: Vec<usize> = (0..SEAT_COUNT).filter(|&s| s != me && n[s] > 0 && !void[s][suit(c) as usize]).collect();
            if seats.is_empty() {
                ok = false;
                break;
            }
            let total: usize = seats.iter().map(|&s| n[s]).sum();
            let mut pick = rng.below(total);
            let mut chosen = seats[0];
            for &s in &seats {
                if pick < n[s] {
                    chosen = s;
                    break;
                }
                pick -= n[s];
            }
            h[chosen].push(c);
            n[chosen] -= 1;
        }
        if ok {
            let mut world = round.clone();
            world.hands = h;
            return Some(world);
        }
    }
    None
}

fn play_out(mut round: Round, bots: &mut [Bot]) -> [i32; SEAT_COUNT] {
    while !round.complete() {
        let seat = round.to_act();
        if round.choosing_moon() {
            round.choose_moon(true);
            continue;
        }
        let view = round.view_for(seat);
        let c = bots[seat].choose_play(&view, None, None);
        round.play(seat, c).unwrap();
    }
    round.points()
}

#[derive(Default)]
struct Tally {
    n: usize,
    regret: f64,
    wrong: usize,
}

pub fn run(deals: usize, seed: u64, threads: usize, rules: Rules, p: &Params, field: Level, worlds: usize, level: Level) {
    let parts: Vec<BTreeMap<String, Tally>> = std::thread::scope(|scope| {
        (0..threads)
            .map(|t| {
                scope.spawn(move || {
                    let mut tally: BTreeMap<String, Tally> = BTreeMap::new();
                    let mut index = t;
                    while index < deals {
                        let seat = index % SEAT_COUNT;
                        let (mut round, mut bots) = duplicate_setup(seed, index, seat, level, field, rules, p);
                        let mut rng = Rng::new(seed * 7_777 + index as u64);
                        let levels: [Level; SEAT_COUNT] = std::array::from_fn(|s| if s == seat { level } else { field });
                        while !round.complete() {
                            let s = round.to_act();
                            if round.choosing_moon() {
                                round.choose_moon(true);
                                continue;
                            }
                            let view = round.view_for(s);
                            let c = bots[s].choose_play(&view, None, None);
                            if s == seat && view.legal.len() > 1 {
                                let why = bots[s].why.get();
                                let mut sums = vec![0f64; view.legal.len()];
                                let mut count = 0;
                                for _ in 0..worlds {
                                    let Some(world) = sample_world(&round, seat, &mut rng) else { continue };
                                    count += 1;
                                    for (i, &m) in view.legal.iter().enumerate() {
                                        let mut w = world.clone();
                                        w.play(seat, m).unwrap();
                                        let mut rollout: Vec<Bot> = levels.iter().map(|&l| Bot::new(l, p, None)).collect();
                                        sums[i] += play_out(w, &mut rollout)[seat] as f64;
                                    }
                                }
                                if count > 0 {
                                    let chosen = view.legal.iter().position(|&m| m == c).unwrap();
                                    let best = sums.iter().cloned().fold(f64::INFINITY, f64::min);
                                    let regret = (sums[chosen] - best) / count as f64;
                                    let phase = match view.hand.len() {
                                        10..=13 => "early",
                                        5..=9 => "mid",
                                        _ => "late",
                                    };
                                    if std::env::var("SHOW").map_or(false, |v| v == why) && regret > 1.5 {
                                        let best_i = sums.iter().position(|&x| x == best).unwrap();
                                        let mut hand = view.hand.clone();
                                        in_display_order(&mut hand);
                                        let evs: Vec<String> = view.legal.iter().zip(&sums).map(|(&m, &x)| format!("{}={:.1}", to_s(m), x / count as f64)).collect();
                                        eprintln!(
                                            "deal {index} seat {seat} stik {} trick [{}] hand [{}] chose {} best {} | {}",
                                            round.tricks.len() + 1,
                                            round.trick.iter().map(|&c| to_s(c)).collect::<Vec<_>>().join(" "),
                                            hand.iter().map(|&c| to_s(c)).collect::<Vec<_>>().join(" "),
                                            to_s(c),
                                            to_s(view.legal[best_i]),
                                            evs.join(" ")
                                        );
                                    }
                                    for key in [format!("{why}"), format!("{why} {phase}")] {
                                        let e = tally.entry(key).or_default();
                                        e.n += 1;
                                        e.regret += regret;
                                        if regret > 0.0 {
                                            e.wrong += 1;
                                        }
                                    }
                                }
                            }
                            round.play(s, c).unwrap();
                        }
                        index += threads;
                    }
                    tally
                })
            })
            .collect::<Vec<_>>()
            .into_iter()
            .map(|h| h.join().unwrap())
            .collect()
    });
    let mut total: BTreeMap<String, Tally> = BTreeMap::new();
    for part in parts {
        for (k, v) in part {
            let e = total.entry(k).or_default();
            e.n += v.n;
            e.regret += v.regret;
            e.wrong += v.wrong;
        }
    }
    let runder = deals as f64;
    println!("regret of {} vs 3 × {}: {} deals, {} worlds per choice", level.name(), field.name(), deals, worlds);
    println!("  {:<28} {:>8} {:>10} {:>9} {:>14}", "rule", "choices", "not best", "regret", "pts per runde");
    let mut rows: Vec<_> = total.iter().collect();
    rows.sort_by(|a, b| b.1.regret.partial_cmp(&a.1.regret).unwrap());
    for (k, v) in rows {
        println!("  {:<28} {:8} {:9.0}% {:9.2} {:14.3}", k, v.n, 100.0 * v.wrong as f64 / v.n as f64, v.regret / v.n as f64, v.regret / runder);
    }
}

/// `botlab voids`: after the pass, how often is the giver void in a suit,
/// by how many cards of it the seat received from the giver; and how often
/// is any other seat void, against the random-deal odds.
pub fn void_stats(deals: usize, seed: u64, rules: Rules, p: &Params, field: Level) {
    let mut by_k = [[0usize; 2]; 4]; // [received k][void?, total]
    let mut other = [[0usize; 2]; 4]; // per suit: seats that are neither giver nor receiver
    let mut any = [[0usize; 2]; 4];
    for index in 0..deals {
        let (round, _) = duplicate_setup(seed, index, 0, field, field, rules, p);
        if round.pass_direction == PassDirection::None {
            for s in 0..SEAT_COUNT {
                for su in 0..4u8 {
                    any[su as usize][1] += 1;
                    if !round.hands[s].iter().any(|&c| suit(c) == su) {
                        any[su as usize][0] += 1;
                    }
                }
            }
            continue;
        }
        for me in 0..SEAT_COUNT {
            let giver = PassDirection::giver(me, round.pass_direction);
            let receiver = PassDirection::receiver(me, round.pass_direction);
            let received = round.passes[giver].unwrap();
            for su in 0..4u8 {
                if su == HEARTS {
                    continue;
                }
                let k = received.iter().filter(|&&c| suit(c) == su).count();
                let void = !round.hands[giver].iter().any(|&c| suit(c) == su);
                by_k[k][1] += 1;
                by_k[k][0] += void as usize;
                for o in 0..SEAT_COUNT {
                    if o != me && o != giver && o != receiver {
                        other[su as usize][1] += 1;
                        other[su as usize][0] += (!round.hands[o].iter().any(|&c| suit(c) == su)) as usize;
                    }
                }
            }
        }
    }
    println!("giver void in a suit (not hearts) after passing me k cards of it, field {}:", field.name());
    for k in 0..4 {
        if by_k[k][1] > 0 {
            println!("  k={k}: {:.3} ({} cases)", by_k[k][0] as f64 / by_k[k][1] as f64, by_k[k][1]);
        }
    }
    println!("third seat void (passing rounds) / any seat void (no pass), per suit C D H S:");
    for su in 0..4 {
        let f = |a: [usize; 2]| if a[1] == 0 { 0.0 } else { a[0] as f64 / a[1] as f64 };
        println!("  {}: {:.3} / {:.3}", SUITS[su] as char, f(other[su]), f(any[su]));
    }
}
