"""Checks the Python Svær against the Ruby one (Esmakker::Svaer) on spil
recorded from Ruby (svaer_parity_record.rb): each runde's log is replayed
on this engine, and at every step a Svær seat took, this Svær decides from
that seat's observation; its action and its thought must be Ruby's.

    python -m esmakker_ai.svaer_parity tmp/esmakker_svaer_parity.jsonl.gz
"""

import sys
from collections import Counter

from . import actions as A
from . import cards as C
from .engine import Round
from .observation import observe
from .parity import read_spil
from .rules import Rules
from .svaer import Svaer


def same_thought(ruby, mine):
    def norm(value):
        if isinstance(value, dict):
            return {k: norm(v) for k, v in value.items()}
        if isinstance(value, float) and value.is_integer():
            return int(value)
        return value
    return norm(ruby) == norm(mine)


def check_runde(rules, svaer_seats, runde, bot, reasons):
    r = Round(C.parse_deal(runde["deal"]), runde["dealer"], rules)
    thoughts = runde["thoughts"]
    problems = []
    decisions = 0
    for index, (seat, action) in enumerate(A.parse_log(runde["actions"])):
        ruby = thoughts.get(str(index))
        if ruby is not None:
            decisions += 1
            mine, thought = bot.decide(observe(r, seat))
            reasons[(ruby["decision"], ruby["reason"])] += 1
            if mine is None or A.token(mine) != A.token(action):
                problems.append(f"step {index} seat {seat}: {None if mine is None else A.token(mine)} != ruby {A.token(action)} "
                                f"(ruby {ruby['reason']}, mine {thought and thought['reason']})")
            elif not same_thought(ruby, thought):
                problems.append(f"step {index} seat {seat}: thought {thought} != ruby {ruby}")
            if problems:
                return problems, decisions
        elif seat in svaer_seats and action != A.BANKSLUT:
            problems.append(f"step {index}: Svær seat {seat} acted without a thought")
            return problems, decisions
        r.apply(seat, action)
    return problems, decisions


def run(path, verbose=True, limit_report=10):
    bot = Svaer()
    spil = runder = decisions = failures = 0
    reasons = Counter()
    for record in read_spil(path):
        spil += 1
        rules = Rules.from_dict(record["rules"])
        for index, runde in enumerate(record["runder"]):
            runder += 1
            problems, count = check_runde(rules, set(record["svaer"]), runde, bot, reasons)
            decisions += count
            if problems:
                failures += 1
                if verbose and failures <= limit_report:
                    print(f"spil seed {record['seed']} runde {index}: " + "; ".join(problems[:3]))
    if verbose:
        print(f"{spil} spil, {runder} runder, {decisions} Svær decisions: {failures} mismatching runder")
        for key in sorted(reasons):
            print(f"  {key[0]:16} {key[1]:18} {reasons[key]}")
    return {"spil": spil, "runder": runder, "decisions": decisions, "failures": failures, "reasons": reasons}


def main(argv):
    if len(argv) != 2:
        print(__doc__)
        return 2
    return 1 if run(argv[1])["failures"] else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
