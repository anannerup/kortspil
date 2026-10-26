"""The net's input, encoded straight from the engine's state (no
observation dict), with the visibility rules of observation.py: a seat's
features hold only what that seat may know (strategy doc §3, "Botten kigger
aldrig"). tests/test_features.py proves it by the same hidden-world swaps as
tests/test_observation.py.

Everything is a bit, so a state is one Python int of STATE_BITS bits
(stdlib only; `to_bytes` packs it for the learner). Seats are relative to
the seat that encodes: relative seat k is (seat + k) % 4, so 0 is the seat
itself, 1 the next clockwise.

An action is the engine's action int (actions.py), "lay away card c"
(DISCARD + c), "lay away no more" (DISCARD_STOP) or "no fordækt"
(NO_FORDAEKT). A discard is chosen one card at a time, the cards chosen so
far in the state (`chosen`), until the seat chooses DISCARD_STOP or has
chosen as many as it may: so it chooses how many it exchanges (0-3, REGLER
§2.0) as well as which. NO_FORDAEKT is the melder's answer when she is
offered fordækt out of turn (she is not forhånd, and the forhånd has not
led yet) and lays none.

The spil context (spil.py) comes last: the runde's place in its spil and
the standing, relative to the seat (public: every seat sees the totals).
Without one, a runde is the first of a spil of SPIL_RUNDER at 0-0-0-0.

FORMAT numbers this layout (state bits, action ids). A checkpoint of
another FORMAT does not load: the run must start anew (learner.py), or,
from FORMAT 2, start from its net (`train start --init`): FORMAT 3 is
FORMAT 2 with the spil context appended, so the old input columns are the
first FORMAT2_STATE_BITS of the new.
"""

from . import actions as A
from . import cards as C
from . import meldinger as M
from .spil import START
from .engine import (BANKING, BIDDING, CALLING_ACE, CHOOSING_TRUMP, COMPLETE, DISCARDING, EXCHANGING, PLAYING,
                     REDEAL, TURNING)

PHASES = (BIDDING, REDEAL, CHOOSING_TRUMP, CALLING_ACE, TURNING, DISCARDING, BANKING, EXCHANGING, PLAYING, COMPLETE)
PHASE_INDEX = {p: i for i, p in enumerate(PHASES)}
PAHAENG_ORDERS = (("vip", "halve", "gode"), ("vip", "gode", "halve"), ("halve", "vip", "gode"),
                  ("halve", "gode", "vip"), ("gode", "vip", "halve"), ("gode", "halve", "vip"))

# The bord's rules the net sees: (Rules attribute, its values). Each value
# gets one bit. Training plays only the house rules (REGLER §2.0, Rules():
# "hvis man spiller med bots spiller man med husets regler", Anders), so
# these bits are constant for now; they are kept so a net can learn other
# bords later without a new FORMAT. A new bord rule is one line here,
# appended at the end, within the 32 reserved bits. A rule Rules does not
# have yet reads as its first value.
RULE_FEATURES = (
    ("joker_trumpable", (False, True)),
    ("esmakker_banks_first", (False, True)),
    ("pahaeng_order", PAHAENG_ORDERS),
    ("afkast", ("renonce", "spil_den_her")),
)

FORMAT = 3  # 1: the first layout; 2: DISCARD_STOP, NO_FORDAEKT, EXCHANGED, BANKERS; 3: the spil context

DISCARD = A.ACTION_COUNT  # DISCARD + card: lay that card away (one of a discard's cards)
DISCARD_STOP = DISCARD + C.DECK_SIZE  # 210: lay away no more (exchange the cards chosen so far)
NO_FORDAEKT = DISCARD_STOP + 1  # 211: offered fordækt out of turn, lay none
ACTION_KINDS = NO_FORDAEKT + 1  # 212


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
EXCHANGED = _L.add("exchanged", 4 * 5)                          # rel seat k * 5 + how many it exchanged (0-3; 4: none yet)
BANKERS = _L.add("bankers", 4)                                  # rel seat k banked
RULES = _L.add("rules", 32)                                     # bord rules (RULE_FEATURES), room to grow
FORMAT2_STATE_BITS = (_L.size + 7) // 8 * 8                     # FORMAT 2 ended here (1192)
_L.size = FORMAT2_STATE_BITS
# the spil context (FORMAT 3), relative to the seat. A difference in points is a
# thermometer: one bit per threshold it reaches, upwards and downwards.
SPIL_SLOTS = 16
DIFF_THRESHOLDS = (0.5, 1, 2, 3, 5, 7, 10, 14, 19, 25, 35, 50)
DIFF_WIDTH = 2 * len(DIFF_THRESHOLDS)
RUNDER_LEFT = _L.add("runder_left", SPIL_SLOTS)                 # this one included: 1, 2, ... 16 or more
RUNDE_NO = _L.add("runde_no", SPIL_SLOTS)                       # runder played before: 0, 1, ... 15 or more
BEHIND = [None] + [_L.add(f"behind{k}", DIFF_WIDTH) for k in (1, 2, 3)]  # rel seat k's total - own
LEAD = _L.add("lead", DIFF_WIDTH)                               # own total - the best other total
RANK = _L.add("rank", 4)                                        # how many seats are strictly ahead
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
    if DISCARD <= action < DISCARD_STOP:
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


# _REL[seat][s]: absolute seat s relative to seat
_REL = tuple(tuple((s - seat) % 4 for s in range(4)) for seat in range(4))

# The part of a seat's state that stays the same through the stik
# (everything but the hand, the stik, the stik won, the esmakker once
# known, the fordækt card still waiting, and at sol the open hand and who
# went down), per runde and seat. A runde in play is told by its first
# stik: that tuple is made once, by the Round that plays it, and shared
# only by its clones made after it (search rollouts), which all have the
# same meldingsrunde and declaration. The entry keeps the tuple, so its id
# is not reused while cached.
_STATIC_CACHE = {}


def encode(r, seat, chosen=0, spil=None):
    """The state as `seat` may know it, an int of STATE_BITS bits. `chosen`
    is a bitmask of the cards already chosen for the discard in progress;
    `spil` the runde's SpilContext (None: the first runde of a spil)."""
    phase = r.phase
    tricks = r.tricks
    if phase == PLAYING and tricks:
        first = tricks[0]
        key = (id(first), seat)
        entry = _STATIC_CACHE.get(key)
        if entry is None or entry[0] is not first or (entry[1] is not spil and entry[1] != spil):
            if len(_STATIC_CACHE) > 100_000:
                _STATIC_CACHE.clear()
            entry = _STATIC_CACHE[key] = (first, spil, _static_bits(r, seat, spil))
        x = entry[2]
    else:
        x = _static_bits(r, seat, spil)
    x |= 1 << (PHASE + PHASE_INDEX[phase]) | r.hands[seat] << HAND | chosen << CHOSEN
    melder = r.melder
    if melder is None:
        return x

    rel = _REL[seat]
    if r.esmakker_known(seat):
        x |= 1 << (ESMAKKER + (4 if r.esmakker is None else rel[r.esmakker]))
    else:
        x |= 1 << (ESMAKKER + 5)
    if r.kind == "sol":
        for s in r.vaeltet():
            x |= 1 << (VAELTET + rel[s])
        if tricks and r.melding in M.OPEN_HAND:
            x |= r.hands[melder] << OPEN_HAND
    elif r.fordaekt is not None and not r.fordaekt_played:
        x |= 1 << (FORDAEKT_FLAGS + 1)

    # the stik
    won = r.tricks_won
    x |= (((1 << won[seat]) - 1) << TRICKS_WON | ((1 << won[(seat + 1) % 4]) - 1) << (TRICKS_WON + 13)
          | ((1 << won[(seat + 2) % 4]) - 1) << (TRICKS_WON + 26)
          | ((1 << won[(seat + 3) % 4]) - 1) << (TRICKS_WON + 39))
    if phase == PLAYING:
        x |= 1 << (TRICK_LEADER + rel[r.trick_leader])
    hide = seat != melder
    if tricks:
        x |= _tricks_bits(tricks, seat, hide)
    if r.trick:
        x |= _plays_bits(r.trick, seat, hide, TRICK, TRICK_DOWN, True)
    return x


def _static_bits(r, seat, spil):
    """encode's bits that stay the same while the stik are played (see
    _STATIC_CACHE)."""
    rel = _REL[seat]
    x = spil_bits(spil or START, seat)
    x |= _rule_bits(r.rules) << RULES
    x |= 1 << (DEALER + rel[r.dealer]) | 1 << (FORHAND + rel[r.forhand])
    x |= _exchanged_bits(r, seat)

    # the meldingsrunde (public)
    x |= 1 << (MELDING + (M.COUNT if r.melding is None else r.melding))
    x |= 1 << (HOLDER + (4 if r.holder is None else rel[r.holder]))
    x |= 1 << (SERVERET + (4 if r.serveret is None else rel[r.serveret]))
    for s in r.passed:
        x |= 1 << (PASSED + rel[s])
    if r.went_with_log:
        for s in r.went_with():
            x |= 1 << (WENT_WITH + rel[s])
    bids = [M.COUNT] * 4
    for s, action in r.history:
        if action < A.PAS:
            bids[rel[s]] = action
        elif action == A.SELV:
            x |= 1 << (SAID_SELV + rel[s])
    x |= 1 << (BIDS[0] + bids[0]) | 1 << (BIDS[1] + bids[1]) | 1 << (BIDS[2] + bids[2]) | 1 << (BIDS[3] + bids[3])

    melder = r.melder
    if melder is None:
        return x | _NO_MELDER

    x |= 1 << (MELDER + rel[melder])
    sol = r.kind == "sol"
    x |= 1 << (KIND + (2 if sol else 1))
    x |= 1 << (TRUMP + (5 if r.trump is None else r.trump))
    x |= 1 << (CALLED + (4 if r.called_ace is None else r.called_ace))
    x |= 1 << (BANKS + len(r.banks))
    for s in r.banks:
        x |= 1 << (BANKERS + rel[s])
    x |= 1 << (VIP_CARD + (r.vip_card or 0))

    # the kitty and the discards, as far as the seat saw them
    # Only what the engine says the seat holds (r.hand) or has seen
    # (kitty_seen): never the kitty itself, so when the engine has the
    # declarer lay away before she takes up the kitty (Anders, 26 October
    # 2026; branch kitty-order), the features follow without a change here.
    x |= C.mask(r.kitty_seen[seat]) << KITTY_KNOWN
    if r.phase == EXCHANGING:
        x |= 1 << (KITTY_LEFT + len(r.kitty))
    if sol:
        x |= C.mask(r.laid_away[seat]) << LAID_AWAY
        for s in r.players:
            x |= 1 << (SOL_PLAYERS + rel[s])
    else:
        if r.discarded and seat == r.declarer():
            x |= C.mask(r.discarded) << LAID_AWAY
        if r.turned:
            x |= C.mask(r.kitty[:r.turned]) << TURNED
        if r.fordaekt is not None:
            x |= 1 << FORDAEKT_FLAGS  # laid (still waiting: encode)
            if seat == melder:
                x |= 1 << (FORDAEKT_FACE + r.fordaekt)
    return x


_NO_MELDER = (1 << (MELDER + 4) | 1 << KIND | 1 << (TRUMP + 5) | 1 << (CALLED + 4) | 1 << (ESMAKKER + 5)
              | 1 << BANKS | 1 << VIP_CARD)


def _diff_bits(diff):
    x = 0
    for i, t in enumerate(DIFF_THRESHOLDS):
        if diff >= t:
            x |= 1 << i
        elif diff <= -t:
            x |= 1 << (len(DIFF_THRESHOLDS) + i)
    return x


_SPIL_CACHE = {}


def spil_bits(spil, seat):
    """The spil context's bits for the seat (cached: one context serves a
    runde's every decision)."""
    key = (spil, seat)
    x = _SPIL_CACHE.get(key)
    if x is None:
        if len(_SPIL_CACHE) > 100_000:
            _SPIL_CACHE.clear()
        played, runder, totals = spil
        own = totals[seat]
        others = [totals[(seat + k) % 4] for k in (1, 2, 3)]
        x = 1 << (RUNDER_LEFT + min(max(runder - played, 1), SPIL_SLOTS) - 1)
        x |= 1 << (RUNDE_NO + min(played, SPIL_SLOTS - 1))
        for k, total in enumerate(others, 1):
            x |= _diff_bits(total - own) << BEHIND[k]
        x |= _diff_bits(own - max(others)) << LEAD
        x |= 1 << (RANK + sum(1 for t in others if t > own))
        _SPIL_CACHE[key] = x
    return x


_NONE_EXCHANGED = sum(1 << (EXCHANGED + 5 * k + 4) for k in range(4))


def _exchanged_bits(r, seat):
    """How many cards each seat exchanged with the kitty, public (REGLER
    §2.0: "Alle kan se, hvor mange melderen byttede"): at a stik melding
    the declarer's count, at a sol-melding each who has had her turn."""
    if r.kind == "stik":
        if r.exchanged is None:
            return _NONE_EXCHANGED
        k = (r.declarer() - seat) % 4
        return _NONE_EXCHANGED & ~(1 << (EXCHANGED + 5 * k + 4)) | 1 << (EXCHANGED + 5 * k + r.exchanged)
    if r.kind == "sol":
        x = _NONE_EXCHANGED
        for s in r.exchange_order[:r.turn]:
            k = (s - seat) % 4
            x = x & ~(1 << (EXCHANGED + 5 * k + 4)) | 1 << (EXCHANGED + 5 * k + len(r.laid_away[s]))
        return x
    return _NONE_EXCHANGED


_TRICKS_CACHE = {}


def _tricks_bits(tricks, seat, hide):
    """The finished stik's bits for the seat, all of them together. A
    stik is a tuple that never changes, made once by the Round that plays
    it and shared by its clones made after it (search rollouts), which all
    have the same stik before it: so the bits of the stik up to and
    including one are cached on that tuple, per seat, and a new stik adds
    its own to the entry of the one before. The entry keeps the tuple, so
    its id is not reused while cached."""
    n = len(tricks)
    i = n
    bits = 0
    while i:
        stik = tricks[i - 1]
        entry = _TRICKS_CACHE.get((id(stik), seat, hide))
        if entry is not None and entry[0] is stik:
            if i == n:
                return entry[1]
            bits = entry[1]
            break
        i -= 1
    if len(_TRICKS_CACHE) > 400_000:
        _TRICKS_CACHE.clear()
    for j in range(i, n):
        stik = tricks[j]
        bits |= _plays_bits(stik[1], seat, hide, PLAYED, PLAYED_DOWN, False)
        _TRICKS_CACHE[(id(stik), seat, hide)] = (stik, bits)
    return bits


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


_RULE_CACHE = {}


def _rule_bits(rules):
    bits = _RULE_CACHE.get(id(rules))
    if bits is None or bits[0] is not rules:
        value, offset = 0, 0
        for name, values in RULE_FEATURES:
            value |= 1 << (offset + values.index(getattr(rules, name, values[0])))
            offset += len(values)
        bits = _RULE_CACHE[id(rules)] = (rules, value)
    return bits[1]


def to_bytes(x):
    return x.to_bytes(STATE_BYTES, "little")


def candidates(r, seat, chosen_cards=()):
    """The action ids the seat chooses among now: its legal actions; at a
    discard DISCARD_STOP and the cards it may still lay away (none once it
    has chosen as many as it may); offered fordækt out of turn,
    NO_FORDAEKT and the fordækt cards. Banking is not a choice: bots never
    bank (strategy §2)."""
    size = r.discard_size(seat)
    if size:
        if len(chosen_cards) >= size:
            return []
        chosen = set(chosen_cards)
        return [DISCARD_STOP] + [DISCARD + card for card in C.cards_of(r.hand(seat)) if card not in chosen]
    legal = [a for a in r.legal_actions(seat) if a != A.BANK]
    if legal and r.phase == PLAYING and seat != r.to_act():
        return [NO_FORDAEKT] + legal  # the melder's fordækt out of turn
    return legal
