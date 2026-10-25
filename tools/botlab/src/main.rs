//! Botlab: the hjerterfri engine, the three bot levels and the bot
//! tournament in Rust, for tuning. Dev only; production runs the Ruby bot
//! (app/models/hjerterfri/bot.rb), which must decide exactly like this one
//! (`botlab parity`). See README.md.

mod bot;
mod card;
mod eval;
mod knowledge;
mod params;
mod parity;
mod regret;
mod rng;
mod round;
mod tournament;

use params::Params;
use round::Rules;

const USAGE: &str = "usage:
  botlab tournament [--spil N] [--seed S] [--threads N] [--end-score N] [--jack]
                    [--<number> X ...]  (any Params number by name, e.g. --safe-shed 0.3)
                    [--off level:rule,...]   (level: let|mellem|svaer|all)
  botlab eval [--spil N] [--fields mellem,svaer] [--levels all] [common flags]
  botlab hands [--deals N] [--field mellem] [--show K] [common flags]
  botlab trace --deal I --seat S [--field mellem] [--levels all] [common flags]
  botlab tune --levels svaer --try 'safe_shed=0.1,0.3;off=svaer:moon' [--deals N] [--fields mellem,svaer]
  botlab regret --levels svaer [--deals N] [--field mellem] [--worlds W]
  botlab voids [--deals N] [--field mellem]
  botlab parity <file.jsonl>
rules for --off: ";

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match args.first().map(String::as_str) {
        Some(cmd @ ("tournament" | "eval" | "hands" | "trace" | "regret" | "voids" | "tune")) => tournament(cmd, &args[1..]),
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

fn tournament(cmd: &str, args: &[String]) {
    let mut spil = 1000;
    let mut fields = vec![params::Level::Mellem, params::Level::Svaer];
    let mut levels = params::LEVELS.to_vec();
    let mut show = 0;
    let mut deal = 0;
    let mut seat = 0;
    let mut worlds = 20;
    let mut tries: Vec<String> = Vec::new();
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
            "--spil" | "--deals" => spil = num() as usize,
            "--fields" | "--field" => fields = eval::parse_levels(value).unwrap_or_else(|| usage()),
            "--levels" => levels = eval::parse_levels(value).unwrap_or_else(|| usage()),
            "--show" => show = num() as usize,
            "--deal" => deal = num() as usize,
            "--seat" => seat = num() as usize,
            "--worlds" => worlds = num() as usize,
            "--seed" => seed = num() as u64,
            "--threads" => threads = num() as usize,
            "--end-score" => rules.end_score = num() as i32,
            "--try" => tries.push(value.to_string()),
            "--off" => p.switch_off(value).unwrap_or_else(|e| {
                eprintln!("{e}");
                usage()
            }),
            f if f.starts_with("--") && p.set(&f[2..], num()) => {}
            _ => usage(),
        }
        i += 2;
    }
    let threads = threads.max(1);
    match cmd {
        "eval" => eval::run(spil, seed, threads, rules, &p, &fields, &levels),
        "hands" => {
            for &field in &fields {
                eval::hands(spil, seed, threads, rules, &p, field, show);
            }
        }
        "regret" => regret::run(spil, seed, threads, rules, &p, fields[0], worlds, levels[levels.len() - 1]),
        "tune" => eval::tune(spil, seed, threads, rules, &p, &fields, levels[levels.len() - 1], &tries),
        "voids" => regret::void_stats(spil, seed, rules, &p, fields[0]),
        "trace" => eval::trace(seed, deal, seat, fields[0], rules, &p, &levels),
        _ => tournament::run(spil, seed, threads, rules, &p),
    }
}
