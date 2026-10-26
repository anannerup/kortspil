"""What one seat may know about a runde (strategy doc §3: "Botten kigger
aldrig"), as a plain dict built from the engine's state.

It holds the seat's own hand, the public actions, the stik played and who
took them, and only what that seat has seen besides: never another seat's
hand, never the kitty unless the seat took it up (or saw it at the
sol-exchange, or it was turned at vip), never another seat's discards, never
the fordækt card's face unless the seat is the melder, and the esmakker only
once the seat knows her (Esmakker::Play#esmakker_known?). It mirrors what
the Ruby Round#view_for shows a player, plus that seat's memory of the
runde (its public action log and what it saw from the kitty).

Hidden things appear as markers:

- in the log, another seat's discard is HIDDEN_DISCARD + n (n cards), a
  fordækt card laid is HIDDEN_FORDAEKT and played is PLAY_FACE_DOWN;
- in a stik, the fordækt card is FACE_DOWN (-1) to everyone but the melder.
"""

from . import actions as A
from . import cards as C
from . import meldinger as M
from .engine import BANKING, DISCARDING, EXCHANGING

FACE_DOWN = -1
HIDDEN_FORDAEKT = A.ACTION_COUNT  # 155
PLAY_FACE_DOWN = A.ACTION_COUNT + 1  # 156
HIDDEN_DISCARD = A.ACTION_COUNT + 2  # 157 + n


def _card_for(r, seat, play):
    """A play in a stik as the seat sees it: (seat, card)."""
    if play[4] and seat != r.melder:
        return (play[0], FACE_DOWN)
    return (play[0], play[1])


def public_log(r, seat):
    melder = r.melder
    fordaekt = r.fordaekt
    out = []
    for actor, action in r.log:
        if isinstance(action, tuple):
            out.append((actor, action if actor == seat else HIDDEN_DISCARD + len(action)))
        elif action >= A.FORDAEKT:
            out.append((actor, action if seat == melder else HIDDEN_FORDAEKT))
        elif (seat != melder and actor == melder and fordaekt is not None
              and action == A.PLAY + fordaekt):
            out.append((actor, PLAY_FACE_DOWN))
        else:
            out.append((actor, action))
    return out


def observe(r, seat):
    known = r.esmakker_known(seat)
    stik_melding = r.kind == "stik"
    sol = r.kind == "sol"
    if stik_melding:
        kitty_count = 0 if r.kitty_taken else C.KITTY_SIZE
        discarded = tuple(r.discarded) if r.discarded and seat == r.declarer() else ()
    else:
        kitty_count = len(r.kitty) if r.phase == EXCHANGING else (0 if sol else C.KITTY_SIZE)
        discarded = r.laid_away[seat]
    if r.phase == DISCARDING and seat == r.declarer():
        kitty_cards = r.kitty_seen[seat]
    elif r.phase == EXCHANGING and seat == r.to_act():
        kitty_cards = tuple(r.kitty)
    else:
        kitty_cards = ()
    fordaekt = None
    if r.fordaekt is not None:
        fordaekt = {"card": r.fordaekt if seat == r.melder else FACE_DOWN, "waiting": r.fordaekt_waiting()}
    open_hand = None
    if sol and r.melding in M.OPEN_HAND and r.tricks:
        open_hand = tuple(C.cards_of(r.hands[r.melder]))
    return {
        "seat": seat,
        "dealer": r.dealer,
        "forhand": r.forhand,
        "rules": r.rules,
        "phase": r.phase,
        "to_act": r.to_act(),
        "hand": tuple(C.cards_of(r.hand(seat))),
        "card_counts": tuple(r.hand(s).bit_count() for s in range(4)),
        "kitty_count": kitty_count,
        "log": public_log(r, seat),
        # the meldingsrunde (public)
        "melding": r.melding,
        "holder": r.holder,
        "serveret": r.serveret,
        "passed": tuple(r.passed),
        "went_with": tuple(r.went_with()),
        "outcome": r.outcome,
        # the play
        "melder": r.melder,
        "trump": r.trump,
        "called_ace": r.called_ace,
        "turned": tuple(r.turned_cards()),
        "vip_card": r.vip_card,
        "bank_window": r.phase == BANKING,
        "banks": tuple(r.banks),
        "esmakker": r.esmakker if known else None,
        "selvmakker": known and r.selvmakker(),
        "kitty_cards": kitty_cards,
        "kitty_seen": r.kitty_seen[seat],
        "discarded": discarded,
        "fordaekt": fordaekt,
        "trick": tuple(_card_for(r, seat, play) for play in r.trick),
        "tricks": tuple((leader, tuple(_card_for(r, seat, play) for play in plays), winner)
                        for leader, plays, winner in r.tricks),
        "tricks_won": tuple(r.tricks_won),
        "open_hand": open_hand,
        "players": r.players,
        "most_stik": M.MOST_STIK[r.melding] if sol else None,
        "vaeltet": tuple(r.vaeltet()) if sol else (),
        # what the seat may do now
        "legal_actions": tuple(r.legal_actions(seat)),
        "discard_size": r.discard_size(seat),
        "result": r.result(),
    }
