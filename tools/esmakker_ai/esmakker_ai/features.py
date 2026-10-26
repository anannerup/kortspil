"""The net's input, encoded straight from the engine's state (no
observation dict), with the visibility rules of observation.py: a seat's
features hold only what that seat may know (strategy doc §3, "Botten kigger
aldrig"). tests/test_features.py proves it by the same hidden-world swaps as
tests/test_observation.py.

Everything is a bit, so a state is one Python int of STATE_BITS bits
(stdlib only; `to_bytes` packs it for the learner). Seats are relative to
the seat that encodes: relative seat k is (seat + k) % 4, so 0 is the seat
itself, 1 the next clockwise.

An action is the engine's action int (actions.py) or "lay away card c"
(DISCARD + c): a discard of N cards is chosen as N single cards in a row,
the cards chosen so far in the state (`chosen`).
"""

from . import actions as A
from . import cards as C
from . import meldinger as M
from .engine import (BANKING, BIDDING, CALLING_ACE, CHOOSING_TRUMP, COMPLETE, DISCARDING, EXCHANGING, PLAYING,
                     REDEAL, TURNING)

PHASES = (BIDDING, REDEAL, CHOOSING_TRUMP, CALLING_ACE, TURNING, DISCARDING, BANKING, EXCHANGING, PLAYING, COMPLETE)
PHASE_INDEX = {p: i for i, p in enumerate(PHASES)}
PAHAENG_ORDERS = (("vip", "halve", "gode"), ("vip", "gode", "halve"), ("halve", "vip", "gode"),
                  ("halve", "gode", "vip"), ("gode", "vip", "halve"), ("gode", "halve", "vip"))

DISCARD = A.ACTION_COUNT  # DISCARD + card: lay that card away (one of a discard's cards)
ACTION_KINDS = A.ACTION_COUNT + C.DECK_SIZE  # 210


class _Layout:
    def __init__(self):
        self.offsets = {}
        self.size = 0

    def add(self, name, width):
        self.offsets[name] = self.size
        self.size += width
        return self.size - width


_L = _Layout()
PHASE = _L.add("phase", len(PHASES))
HAND = _L.add("hand", 55)
PLAYED = [_L.add(f"played{k}", 55) for k in range(4)]          # cards rel seat k played (as seen)
TRICK = [_L.add(f"trick{k}", 55) for k in range(4)]            # rel seat k's card in the stik on the table
TRICK_DOWN = _L.add("trick_face_down", 4)                       # rel seat k played face down in this stik
TRICK_LEADER = _L.add("trick_leader", 4)
PLAYED_DOWN = _L.add("played_face_down", 1)                     # the fordækt card fell in an earlier stik
VOID = _L.add("void", 16)                                       # rel seat k * 4 + suit: shown renonce
TRICKS_WON = _L.add("tricks_won", 4 * 13)                       # thermometer per rel seat
KITTY_KNOWN = _L.add("kitty_known", 55)                         # kitty cards the seat saw
LAID_AWAY = _L.add("laid_away", 55)                             # its own discards
TURNED = _L.add("turned", 55)                                   # vip cards turned (public)
VIP_CARD = _L.add("vip_card", 4)
CHOSEN = _L.add("chosen", 55)                                   # cards chosen so far for a discard
FORDAEKT_FACE = _L.add("fordaekt_face", 55)                     # the melder's own fordækt card
FORDAEKT_FLAGS = _L.add("fordaekt_flags", 2)                    # laid, still waiting
MELDING = _L.add("melding", M.COUNT + 1)
HOLDER = _L.add("holder", 5)
SERVERET = _L.add("serveret", 5)
PASSED = _L.add("passed", 4)
WENT_WITH = _L.add("went_with", 4)
SAID_SELV = _L.add("said_selv", 4)
BIDS = [_L.add(f"bid{k}", M.COUNT + 1) for k in range(4)]      # highest melding rel seat k bid
DEALER = _L.add("dealer", 4)
FORHAND = _L.add("forhand", 4)
MELDER = _L.add("melder", 5)
KIND = _L.add("kind", 3)                                        # none, stik, sol
TRUMP = _L.add("trump", 6)
CALLED = _L.add("called_ace", 5)
ESMAKKER = _L.add("esmakker", 6)                                # rel seat 0-3 once known, selvmakker, unknown
BANKS = _L.add("banks", 3)
SOL_PLAYERS = _L.add("sol_players", 4)
VAELTET = _L.add("vaeltet", 4)
OPEN_HAND = _L.add("open_hand", 55)
KITTY_LEFT = _L.add("kitty_left", 4)                            # cards left in the kitty at the sol exchange
RULES = _L.add("rules", 2 + len(PAHAENG_ORDERS))
STATE_BITS = (_L.size + 7) // 8 * 8
STATE_BYTES = STATE_BITS // 8

A_KIND = 0
A_CARD = ACTION_KINDS
ACTION_BITS = (A_CARD + 55 + 7) // 8 * 8
ACTION_BYTES = ACTION_BITS // 8


def _card_of(action):
    if A.PLAY <= action < A.FORDAEKT:
        return action - A.PLAY
    if A.FORDAEKT <= action < A.ACTION_COUNT:
        return action - A.FORDAEKT
    if action >= DISCARD:
        return action - DISCARD
    return None


def _action_bits(action):
    bits = 1 << (A_KIND + action)
    card = _card_of(action)
    if card is not None:
        bits |= 1 << (A_CARD + card)
    return bits


_ACTION_CACHE = tuple(_action_bits(a) for a in range(ACTION_KINDS))
_ACTION_BYTES_CACHE = tuple(b.to_bytes(ACTION_BYTES, "little") for b in _ACTION_CACHE)


def encode_action(action):
    """An action id (0..ACTION_KINDS-1) as an int of ACTION_BITS bits."""
    return _ACTION_CACHE[action]


def action_bytes(action):
    return _ACTION_BYTES_CACHE[action]


def _rel(s, seat):
    return (s - seat) % 4


def encode(r, seat, chosen=0):
    """The state as `seat` may know it, an int of STATE_BITS bits. `chosen`
    is a bitmask of the cards already chosen for the discard in progress."""
    x = 1 << (PHASE + PHASE_INDEX[r.phase])
    x |= r.hand(seat) << HAND
    melder = r.melder
    rules = r.rules
    x |= (int(rules.joker_trumpable) | int(rules.esmakker_banks_first) << 1) << RULES
    x |= 1 << (RULES + 2 + PAHAENG_ORDERS.index(rules.pahaeng_order))
    x |= 1 << (DEALER + _rel(r.dealer, seat))
    x |= 1 << (FORHAND + _rel(r.forhand, seat))
    x |= chosen << CHOSEN

    # the meldingsrunde (public)
    x |= 1 << (MELDING + (M.COUNT if r.melding is None else r.melding))
    x |= 1 << (HOLDER + (4 if r.holder is None else _rel(r.holder, seat)))
    x |= 1 << (SERVERET + (4 if r.serveret is None else _rel(r.serveret, seat)))
    for s in r.passed:
        x |= 1 << (PASSED + _rel(s, seat))
    for s in r.went_with():
        x |= 1 << (WENT_WITH + _rel(s, seat))
    bids = [M.COUNT] * 4
    for s, action in r.history:
        if action < A.PAS:
            bids[_rel(s, seat)] = action
        elif action == A.SELV:
            x |= 1 << (SAID_SELV + _rel(s, seat))
    for k in range(4):
        x |= 1 << (BIDS[k] + bids[k])

    if melder is None:
        x |= 1 << (MELDER + 4)
        x |= 1 << KIND
        x |= 1 << (TRUMP + 5)
        x |= 1 << (CALLED + 4)
        x |= 1 << (ESMAKKER + 5)
        x |= 1 << BANKS
        x |= 1 << VIP_CARD
        return x

    x |= 1 << (MELDER + _rel(melder, seat))
    sol = r.kind == "sol"
    x |= 1 << (KIND + (2 if sol else 1))
    x |= 1 << (TRUMP + (5 if r.trump is None else r.trump))
    x |= 1 << (CALLED + (4 if r.called_ace is None else r.called_ace))
    x |= 1 << (BANKS + len(r.banks))
    x |= 1 << (VIP_CARD + (r.vip_card or 0))
    if r.esmakker_known(seat):
        x |= 1 << (ESMAKKER + (4 if r.esmakker is None else _rel(r.esmakker, seat)))
    else:
        x |= 1 << (ESMAKKER + 5)

    # the kitty and the discards, as far as the seat saw them
    kitty_known = C.mask(r.kitty_seen[seat])
    if r.phase == EXCHANGING and seat == r.to_act():
        kitty_known |= C.mask(r.kitty)
        x |= 1 << (KITTY_LEFT + len(r.kitty))
    elif r.phase == EXCHANGING:
        x |= 1 << (KITTY_LEFT + len(r.kitty))
    x |= kitty_known << KITTY_KNOWN
    if sol:
        x |= C.mask(r.laid_away[seat]) << LAID_AWAY
        for s in r.players:
            x |= 1 << (SOL_PLAYERS + _rel(s, seat))
        for s in r.vaeltet():
            x |= 1 << (VAELTET + _rel(s, seat))
        if r.melding in M.OPEN_HAND and r.tricks:
            x |= r.hands[melder] << OPEN_HAND
    else:
        if r.discarded and seat == r.declarer():
            x |= C.mask(r.discarded) << LAID_AWAY
        if r.turned:
            x |= C.mask(r.kitty[:r.turned]) << TURNED
        if r.fordaekt is not None:
            x |= (1 | int(r.fordaekt_waiting()) << 1) << FORDAEKT_FLAGS
            if seat == melder:
                x |= 1 << (FORDAEKT_FACE + r.fordaekt)

    # the stik
    for k in range(4):
        x |= ((1 << r.tricks_won[(seat + k) % 4]) - 1) << (TRICKS_WON + 13 * k)
    if r.phase == PLAYING:
        x |= 1 << (TRICK_LEADER + _rel(r.trick_leader, seat))
    hide = seat != melder
    for _, plays, _ in r.tricks:
        x |= _plays_bits(plays, seat, hide, PLAYED, PLAYED_DOWN, False)
    if r.trick:
        x |= _plays_bits(r.trick, seat, hide, TRICK, TRICK_DOWN, True)
    return x


def _plays_bits(plays, seat, hide, card_offsets, down_offset, per_seat_down):
    x = 0
    led = plays[0][2]
    for s, card, suit, _, face_down in plays:
        k = (s - seat) % 4
        if face_down and hide:
            x |= 1 << (down_offset + (k if per_seat_down else 0))
        else:
            x |= 1 << (card_offsets[k] + card)
        if led >= 0 and suit >= 0 and suit != led:
            x |= 1 << (VOID + 4 * k + led)
    return x


def to_bytes(x):
    return x.to_bytes(STATE_BYTES, "little")


def candidates(r, seat, chosen_cards=()):
    """The action ids the seat chooses among now: its legal actions, or at a
    discard the cards it may still lay away. Banking is not a choice: bots
    never bank (strategy §2)."""
    size = r.discard_size(seat)
    if size:
        chosen = set(chosen_cards)
        return [DISCARD + card for card in C.cards_of(r.hand(seat)) if card not in chosen]
    return [a for a in r.legal_actions(seat) if a != A.BANK]
