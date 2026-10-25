//! `botlab parity <file>`: recompute every decision the Ruby bots made
//! (recorded by `bin/rails 'bots:parity[...]'`) and report mismatches.
//!
//! Lines are JSON objects with a "kind":
//! - "pass":  {level, hand, choice}
//! - "play":  {level, view, totals, end_score, choice}
//! - "moon":  {seat, totals, choice}
//! - "runde": {levels, rules, deal, pass_direction, passes, plays, totals,
//!             end_score, game_totals, points}: the whole runde is replayed
//!             with the Rust engine and Rust bots and must come out the same.

use crate::bot::Bot;
use crate::card::{self, Card};
use crate::params::{Level, Params};
use crate::round::{DoneTrick, PassDirection, Play, Round, Rules, View, SEAT_COUNT};
use serde_json::Value;
use std::io::BufRead;

fn cards(v: &Value) -> Vec<Card> {
    v.as_array()
        .map(|a| a.iter().map(|c| card::parse(c.as_str().unwrap()).expect("card code")).collect())
        .unwrap_or_default()
}

fn plays(v: &Value) -> Vec<Play> {
    v.as_array()
        .map(|a| {
            a.iter()
                .map(|p| Play { seat: p["seat"].as_u64().unwrap() as usize, card: card::parse(p["card"].as_str().unwrap()).unwrap() })
                .collect()
        })
        .unwrap_or_default()
}

fn rules(v: &Value) -> Rules {
    Rules {
        end_score: v["end_score"].as_i64().unwrap_or(100) as i32,
        queen_breaks_hearts: v["queen_breaks_hearts"].as_bool().unwrap_or(false),
        jack_of_diamonds_minus_ten: v["jack_of_diamonds_minus_ten"].as_bool().unwrap_or(false),
        shooters_choice: v["shooters_choice"].as_bool().unwrap_or(false),
    }
}

fn totals(v: &Value) -> Option<[i32; SEAT_COUNT]> {
    let a = v.as_array()?;
    Some(std::array::from_fn(|i| a[i].as_i64().unwrap() as i32))
}

pub fn view(v: &Value) -> View {
    let mut card_counts = [0; SEAT_COUNT];
    if let Some(counts) = v["card_counts"].as_object() {
        for (seat, n) in counts {
            card_counts[seat.parse::<usize>().unwrap()] = n.as_u64().unwrap() as usize;
        }
    }
    View {
        seat: v["seat"].as_u64().unwrap() as usize,
        hand: cards(&v["hand"]),
        legal: cards(&v["legal_moves"]),
        trick: plays(&v["current_trick"]),
        tricks: v["tricks"]
            .as_array()
            .map(|a| a.iter().map(|t| DoneTrick { plays: plays(&t["plays"]), winner: t["winner"].as_u64().unwrap() as usize }).collect())
            .unwrap_or_default(),
        rules: rules(&v["rules"]),
        hearts_broken: v["hearts_broken"].as_bool().unwrap_or(false),
        pass_direction: PassDirection::parse(v["pass_direction"].as_str().unwrap_or("none")),
        own_pass: cards(&v["own_pass"]),
        received: cards(&v["received_cards"]),
        card_counts,
    }
}

fn level(v: &Value) -> Level {
    Level::parse(v.as_str().unwrap()).expect("level")
}

fn codes(cards: &[Card]) -> String {
    cards.iter().map(|&c| card::to_s(c)).collect::<Vec<_>>().join(" ")
}

pub fn run(path: &str) -> bool {
    let p = Params::default();
    let file = std::fs::File::open(path).unwrap_or_else(|e| panic!("{path}: {e}"));
    let mut counts = std::collections::BTreeMap::<String, (usize, usize)>::new();
    let mut shown = 0;
    let mut report = |kind: String, ok: bool, detail: &dyn Fn() -> String| {
        let entry = counts.entry(kind).or_default();
        entry.0 += 1;
        if !ok {
            entry.1 += 1;
            if shown < 20 {
                println!("MISMATCH {}", detail());
                shown += 1;
            }
        }
    };
    for (number, line) in std::io::BufReader::new(file).lines().enumerate() {
        let line = line.unwrap();
        if line.trim().is_empty() {
            continue;
        }
        let d: Value = serde_json::from_str(&line).expect("json line");
        let kind = d["kind"].as_str().unwrap().to_string();
        match kind.as_str() {
            "pass" => {
                let l = level(&d["level"]);
                let hand = cards(&d["hand"]);
                let expected = cards(&d["choice"]);
                let got = Bot::new(l, &p, None).choose_pass(&hand);
                report(format!("pass {}", l.name()), got == expected, &|| {
                    format!("line {}: {} pass from [{}]: ruby [{}], rust [{}]", number + 1, l.name(), codes(&hand), codes(&expected), codes(&got))
                });
            }
            "play" => {
                let l = level(&d["level"]);
                let v = view(&d["view"]);
                let expected = card::parse(d["choice"].as_str().unwrap()).unwrap();
                let got = Bot::new(l, &p, None).choose_play(&v, totals(&d["totals"]), d["end_score"].as_i64().map(|e| e as i32));
                report(format!("play {}", l.name()), got == expected, &|| {
                    format!(
                        "line {}: {} play: ruby {}, rust {}\n  totals {} end_score {}\n  view {}",
                        number + 1,
                        l.name(),
                        card::to_s(expected),
                        card::to_s(got),
                        d["totals"],
                        d["end_score"],
                        d["view"]
                    )
                });
            }
            "moon" => {
                let t = totals(&d["totals"]).unwrap();
                let seat = d["seat"].as_u64().unwrap() as usize;
                let add = Bot::new(Level::Mellem, &p, None).choose_moon(seat, &t);
                let got = if add { "add_to_others" } else { "subtract_from_self" };
                report("moon".into(), got == d["choice"].as_str().unwrap(), &|| format!("line {}: moon {}", number + 1, line));
            }
            "runde" => {
                let result = replay_runde(&d, &p);
                report("runde".into(), result.is_ok(), &|| format!("line {}: runde {}", number + 1, result.clone().err().unwrap()));
            }
            other => panic!("unknown kind {other}"),
        }
    }
    let mut all_ok = true;
    for (kind, (n, bad)) in &counts {
        println!("{:<14} {:6} decisions  {:4} mismatches", kind, n, bad);
        all_ok &= *bad == 0;
    }
    let total: usize = counts.values().map(|c| c.0).sum();
    let bad: usize = counts.values().map(|c| c.1).sum();
    println!("{} decisions, {} mismatches", total, bad);
    all_ok
}

fn replay_runde(d: &Value, p: &Params) -> Result<(), String> {
    let levels: Vec<Level> = d["levels"].as_array().unwrap().iter().map(level).collect();
    let rules = rules(&d["rules"]);
    let dealt: [Vec<Card>; SEAT_COUNT] = std::array::from_fn(|s| cards(&d["deal"][s]));
    let direction = PassDirection::parse(d["pass_direction"].as_str().unwrap());
    let t = totals(&d["totals"]);
    let end_score = d["end_score"].as_i64().map(|e| e as i32);
    let mut bots: Vec<Bot> = levels.iter().map(|&l| Bot::new(l, p, None)).collect();
    let mut round = Round::new(rules, dealt, direction);
    if round.passing() {
        for seat in 0..SEAT_COUNT {
            let pass = bots[seat].choose_pass(&round.view_for(seat).hand);
            let expected = cards(&d["passes"][seat]);
            if pass != expected {
                return Err(format!("seat {seat} passed [{}], ruby [{}]", codes(&pass), codes(&expected)));
            }
            round.pass(seat, [pass[0], pass[1], pass[2]])?;
        }
    }
    let expected_plays = cards(&d["plays"]);
    while !round.complete() {
        let seat = round.to_act();
        if round.choosing_moon() {
            let add = bots[seat].choose_moon(seat, &totals(&d["game_totals"]).unwrap());
            round.choose_moon(add);
            continue;
        }
        let view = round.view_for(seat);
        let c = bots[seat].choose_play(&view, t, end_score);
        let index = round.plays.len();
        if expected_plays.get(index) != Some(&c) {
            return Err(format!("play {index} by seat {seat}: rust {}, ruby {:?}", card::to_s(c), expected_plays.get(index).map(|&c| card::to_s(c))));
        }
        round.play(seat, c)?;
    }
    let points = round.points();
    let expected: Vec<i32> = d["points"].as_array().unwrap().iter().map(|x| x.as_i64().unwrap() as i32).collect();
    if points.to_vec() != expected {
        return Err(format!("points rust {points:?}, ruby {expected:?}"));
    }
    Ok(())
}
