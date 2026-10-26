"""Replays spil recorded from the Ruby engine (parity_record.rb) and checks
that this engine agrees at every step: phase, seat to act, every seat's
legal actions, who each seat knows the esmakker to be, what one seat's
observation shows (observation.py against Ruby's Round#view_for); and at
the end the
action log, the phase, the next kortgiver, the result and the points, and
the spil's totals.

    python -m esmakker_ai.parity tmp/esmakker_parity.jsonl.gz
"""

import gzip
import json
import sys
from collections import Counter
from fractions import Fraction

from . import actions as A
from . import cards as C
from . import scoring as S
from .engine import EXCHANGING, Round
from .observation import FACE_DOWN, observe
from .rules import Rules


def open_text(path):
    return gzip.open(path, "rt", encoding="utf-8") if str(path).endswith(".gz") else open(path, encoding="utf-8")


def read_spil(path):
    with open_text(path) as lines:
        for line in lines:
            if line.strip():
                yield json.loads(line)


def legal_tokens(round_, seat):
    tokens = sorted(A.token(action) for action in round_.legal_actions(seat))
    size = round_.discard_size(seat)
    if size:
        tokens.append(f"kast:{size}")
    return tokens


def known(round_):
    return [(round_.esmakker if round_.esmakker is not None else -1) if round_.esmakker_known(seat) else None
            for seat in range(4)]


def _codes(cards):
    return sorted(C.code(card) for card in cards)


def _stik(plays):
    return [[seat, "fordaekt" if card == FACE_DOWN else C.code(card)] for seat, card in plays]


def compare_view(r, view):
    """Mismatching parts between Ruby's view_for(seat) (as recorded) and
    the seat's observation here."""
    seat = view["seat"]
    obs = observe(r, seat)
    ruby_fordaekt = view["fordaekt"]
    mine_fordaekt = obs["fordaekt"]
    ruby_open = view["open_hand"]
    pairs = {
        "hand": (sorted(view["hand"]), _codes(obs["hand"])),
        "card_counts": ({int(s): n for s, n in view["card_counts"].items()},
                        {s: n for s, n in enumerate(obs["card_counts"]) if s != seat}),
        "esmakker": (view["esmakker"], obs["esmakker"]),
        "selvmakker": (view["selvmakker"], obs["selvmakker"]),
        "turned": (view["turned"], [C.code(card) for card in obs["turned"]]),
        "kitty_cards": (sorted(view["kitty_cards"]), _codes(obs["kitty_cards"])),
        "discarded": (sorted(view["discarded"]), _codes(obs["discarded"])),
        "current_trick": ([[p["seat"], p["card"]] for p in view["current_trick"]], _stik(obs["trick"])),
        "last_trick": ([[p["seat"], p["card"]] for p in view["last_trick"]],
                       _stik(obs["tricks"][-1][1]) if obs["tricks"] else []),
        "fordaekt": (ruby_fordaekt and (ruby_fordaekt["card"], ruby_fordaekt["waiting"]),
                     mine_fordaekt and (None if mine_fordaekt["card"] == FACE_DOWN else C.code(mine_fordaekt["card"]),
                                        mine_fordaekt["waiting"])),
        "open_hand": (ruby_open and sorted(ruby_open["cards"]),
                      None if obs["open_hand"] is None else _codes(obs["open_hand"])),
    }
    # At a sol-melding Ruby counts the kitty as taken from the start of the
    # exchange; the observation counts what is left of it.
    if r.phase != EXCHANGING:
        pairs["kitty_count"] = (view["kitty_count"], obs["kitty_count"])
    return [f"{key} {mine!r} != ruby {ruby!r}" for key, (ruby, mine) in pairs.items() if ruby != mine]


def same_number(ruby, python):
    """Ruby gives whole amounts as integers and the rest as floats of the
    exact Rational (Scoring.tidy); ours are exact Fractions."""
    if isinstance(ruby, float):
        return Fraction(python).denominator != 1 and float(python) == ruby
    return Fraction(python) == ruby


def compare_result(ruby, python):
    """Mismatching keys between Ruby's result hash and ours."""
    if ruby is None or python is None:
        return [] if ruby is None and python is None else ["result"]
    diffs = []
    for key, value in ruby.items():
        mine = python.get(key)
        if key == "points":
            if len(value) != len(mine) or not all(same_number(a, b) for a, b in zip(value, mine)):
                diffs.append(key)
        elif value != mine:
            diffs.append(key)
    return diffs


def check_runde(rules, runde):
    """Mismatches of one recorded runde, as strings; [] when equal. Returns
    (mismatches, round)."""
    deal = C.parse_deal(runde["deal"])
    log = A.parse_log(runde["actions"])
    r = Round(deal, runde["dealer"], rules)
    problems = []
    for index, ((seat, action), step) in enumerate(zip(log, runde["steps"])):
        where = f"step {index} ({seat}:{A.token(action)})"
        if r.phase != step["phase"]:
            problems.append(f"{where}: phase {r.phase} != ruby {step['phase']}")
        if r.to_act() != step["to_act"]:
            problems.append(f"{where}: to_act {r.to_act()} != ruby {step['to_act']}")
        mine = {str(s): legal_tokens(r, s) for s in range(4)}
        mine = {s: tokens for s, tokens in mine.items() if tokens}
        if mine != step["legal"]:
            problems.append(f"{where}: legal {mine} != ruby {step['legal']}")
        if known(r) != step["known"]:
            problems.append(f"{where}: esmakker known {known(r)} != ruby {step['known']}")
        if "view" in step:
            problems.extend(f"{where}: seat {step['view']['seat']} view {diff}" for diff in compare_view(r, step["view"]))
        if problems:
            return problems, r
        r.apply(seat, action)
    if len(log) != len(runde["steps"]):
        problems.append("steps and actions differ in length")
    if r.tokens() != runde["actions"]:
        problems.append("action log differs")
    if r.phase != runde["phase"]:
        problems.append(f"final phase {r.phase} != ruby {runde['phase']}")
    if r.next_dealer() != runde["next_dealer"]:
        problems.append(f"next dealer {r.next_dealer()} != ruby {runde['next_dealer']}")
    diffs = compare_result(runde["result"], r.result())
    if diffs:
        problems.append(f"result differs in {diffs}: ruby {runde['result']} python {r.result()}")
    return problems, r


def coverage_key(r):
    """What a runde exercised, for the coverage report."""
    keys = []
    if r.phase == "redeal":
        keys.append(f"redeal:{r.outcome[1]}")
        return keys
    keys.append(f"melding:{A.token(A.BID + r.melding)}")
    if r.kind == "stik":
        keys.append(f"trump:{A.trump_code(r.trump)}")
        if r.selvmakker():
            keys.append("selvmakker")
        if r.fordaekt is not None:
            keys.append("fordaekt" + (":joker" if r.fordaekt >= 52 else ""))
        if r.vip_card:
            keys.append(f"vip_card:{r.vip_card}")
        keys.append(f"banks:{len(r.banks)}")
    else:
        keys.append(f"sol_players:{len(r.players)}")
        keys.append(f"sol_vaeltet:{len(r.vaeltet())}")
        keys.append(f"sol_stik:{len(r.tricks)}")
    actions = {a for _, a in r.history}
    for action, name in ((A.SELV, "det_kan_jeg_selv"), (A.MED, "gaa_med")):
        if action in actions:
            keys.append(name)
    return keys


def run(path, verbose=True, limit_report=10):
    spil = runder = steps = failures = 0
    coverage = Counter()
    for record in read_spil(path):
        spil += 1
        rules = Rules.from_dict(record["rules"])
        points = []
        for index, runde in enumerate(record["runder"]):
            runder += 1
            steps += len(runde["steps"])
            problems, r = check_runde(rules, runde)
            if problems:
                failures += 1
                if verbose and failures <= limit_report:
                    print(f"spil seed {record['seed']} runde {index}: " + "; ".join(problems[:3]))
                continue
            coverage.update(coverage_key(r))
            if r.complete():
                points.append(r.points())
        totals = S.total(points)
        if not all(same_number(a, b) for a, b in zip(record["totals"], totals)):
            failures += 1
            if verbose and failures <= limit_report:
                print(f"spil seed {record['seed']}: totals {totals} != ruby {record['totals']}")
    if verbose:
        print(f"{spil} spil, {runder} runder, {steps} steps: {failures} mismatches")
        for key in sorted(coverage):
            print(f"  {key:28} {coverage[key]}")
    return {"spil": spil, "runder": runder, "steps": steps, "failures": failures, "coverage": coverage}


def main(argv):
    if len(argv) != 2:
        print(__doc__)
        return 2
    report = run(argv[1])
    return 1 if report["failures"] else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
