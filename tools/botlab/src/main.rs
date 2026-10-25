//! Botlab: the hjerterfri engine, the three bot levels and the bot
//! tournament in Rust, for tuning. Dev only; production runs the Ruby bot
//! (app/models/hjerterfri/bot.rb), which must decide exactly like this one
//! (`botlab parity`). See README.md.

mod bot;
mod card;
mod knowledge;
mod params;
mod parity;
mod rng;
mod round;
mod tournament;

use params::Params;
use round::Rules;

const USAGE: &str = "usage:
  botlab tournament [--spil N] [--seed S] [--threads N] [--end-score N] [--jack]
                    [--risky X] [--safe X] [--moon-threat N] [--late N] [--high N]
                    [--void-plan-hand N] [--safe-high-hand N]
                    [--discard-evidence X] [--spade-evidence X]
                    [--off level:rule,...]   (level: let|mellem|svaer|all)
  botlab parity <file.jsonl>
rules for --off: ";

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match args.first().map(String::as_str) {
        Some("tournament") => tournament(&args[1..]),
        Some("parity") => {
            let path = args.get(1).unwrap_or_else(|| usage());
            if !parity::run(path) {
                std::process::exit(1);
            }
        }
        _ => usage(),
    }
}

fn usage() -> ! {
    let names: Vec<&str> = params::RULE_NAMES.iter().map(|(n, _)| *n).collect();
    eprintln!("{USAGE}{}", names.join(", "));
    std::process::exit(2)
}

fn tournament(args: &[String]) {
    let mut spil = 1000;
    let mut seed = 1;
    let mut threads = std::thread::available_parallelism().map(|n| n.get()).unwrap_or(4);
    let mut rules = Rules::standard();
    let mut p = Params::default();
    let mut i = 0;
    while i < args.len() {
        let flag = args[i].as_str();
        if flag == "--jack" {
            rules.jack_of_diamonds_minus_ten = true;
            i += 1;
            continue;
        }
        let value = args.get(i + 1).unwrap_or_else(|| usage()).as_str();
        let num = || value.parse::<f64>().unwrap_or_else(|_| usage());
        match flag {
            "--spil" => spil = num() as usize,
            "--seed" => seed = num() as u64,
            "--threads" => threads = num() as usize,
            "--end-score" => rules.end_score = num() as i32,
            "--risky" => p.risky = num(),
            "--safe" => p.safe = num(),
            "--moon-threat" => p.moon_threat = num() as i32,
            "--late" => p.late = num() as usize,
            "--high" => p.high = num() as u8,
            "--void-plan-hand" => p.void_plan_hand = num() as usize,
            "--safe-high-hand" => p.safe_high_hand = num() as usize,
            "--discard-evidence" => p.discard_evidence = num(),
            "--spade-evidence" => p.spade_evidence = num(),
            "--off" => p.switch_off(value).unwrap_or_else(|e| {
                eprintln!("{e}");
                usage()
            }),
            _ => usage(),
        }
        i += 2;
    }
    tournament::run(spil, seed, threads.max(1), rules, &p);
}
