"""Playing runder and spil with bots (the bord's part: deals, the bank
window, redeals, the kortgiver moving on)."""

import random

from . import actions as A
from .engine import BANKING, Round
from .observation import observe
from .rules import STANDARD
from .scoring import total


def random_deal(rng):
    deck = list(range(55))
    rng.shuffle(deck)
    return deck


def bank_window(r, bots, observe_fn=observe):
    """One step of vip's bank window. The engine knows no time: the seats
    offered a bank are asked in turn, clockwise from the melder (before the
    first bank) or the melder alone (after it); if nobody banks the window
    closes ("bankslut", for the melder's seat)."""
    seats = [(r.melder + offset) % 4 for offset in (1, 2, 3)] if not r.banks else [r.melder]
    for seat in seats:
        if A.BANK in r.legal_actions(seat) and bots[seat].act(observe_fn(r, seat)) == A.BANK:
            r.apply(seat, A.BANK)
            return
    r.apply(r.melder, A.BANKSLUT)


def play_runde(r, bots, check=True, observe_fn=observe):
    """Plays the runde to its end (complete or redeal) in place."""
    while not r.over():
        if r.phase == BANKING:
            bank_window(r, bots, observe_fn)
            continue
        seat = r.to_act()
        r.apply(seat, bots[seat].act(observe_fn(r, seat)), check=check)
    return r


def play_spil(bots, runder=10, rules=STANDARD, seed=None, dealer=0, check=True, max_deals=1000):
    """A spil of `runder` played runder; a redealt runde does not count.
    Returns (rounds, totals)."""
    rng = random.Random(seed)
    rounds = []
    played = 0
    while played < runder and len(rounds) < max_deals:
        r = play_runde(Round(random_deal(rng), dealer, rules), bots, check=check)
        rounds.append(r)
        played += r.complete()
        dealer = r.next_dealer()
    return rounds, total([r.points() for r in rounds if r.complete()])
