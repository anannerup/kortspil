"""Playing runder and spil with bots (the bord's part: deals, the bank
window, redeals, the kortgiver moving on)."""

import random

from . import actions as A
from .engine import BANKING, PLAYING, Round
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


def fordaekt_offer(r):
    """The melder, when she may lay fordækt out of turn now: a stik melding,
    she is not the forhånd, and the forhånd has not led the first stik
    (REGLER §2.0, "Fordækt": before the first lead). Else None. (A melder
    who is the forhånd has fordækt among her legal actions at her lead.)"""
    if r.phase != PLAYING or r.kind != "stik" or r.to_act() == r.melder or not r.fordaekt_allowed():
        return None
    return r.melder


def ask_fordaekt(bot, obs):
    """A bot's answer to fordækt out of turn: a FORDAEKT action or None.
    A bot without `offer_fordaekt` lays none."""
    offer = getattr(bot, "offer_fordaekt", None)
    action = offer(obs) if offer else None
    return action if action in obs["legal_actions"] else None


def offer_fordaekt(r, bots, observe_fn=observe):
    """Asks the melder once, before the forhånd leads, whether she lays
    fordækt out of turn; applies it if she does."""
    melder = r.melder
    action = ask_fordaekt(bots[melder], observe_fn(r, melder))
    if action is not None:
        r.apply(melder, action)


def play_runde(r, bots, check=True, observe_fn=observe):
    """Plays the runde to its end (complete or redeal) in place. The melder
    is offered fordækt out of turn once, before the forhånd leads, when she
    is not the forhånd (fordaekt_offer)."""
    offered = False
    while not r.over():
        if r.phase == BANKING:
            bank_window(r, bots, observe_fn)
            continue
        if not offered and fordaekt_offer(r) is not None:
            offered = True
            offer_fordaekt(r, bots, observe_fn)
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
