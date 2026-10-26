"""Svær: the es-makker bot that plays by readable rules
(docs/bots/esmakker-strategy.md §6), the training partner of the net.

The production bot is Esmakker::Svaer (app/models/esmakker/svaer.rb); this
is the same bot, decision for decision, kept equal by the parity check
(`python -m esmakker_ai.svaer_parity`). Change one, change the other.

Svær reads only the seat's observation (observation.py), never banks, and
is deterministic: no randomness, every tie broken by a fixed order. Every
number the doc marks [valgt] lives in SvaerParams, so it can be tuned.
Amounts are exact Fractions (Ruby: Rational), so both sides agree to the
last digit.

    bot = Svaer()
    action = bot.act(obs)                # the engine's action (or None)
    action, thought = bot.decide(obs)    # with the "Vis kort" thought
"""

import math
from dataclasses import dataclass, fields
from functools import lru_cache
from fractions import Fraction as F

from . import actions as A
from . import cards as C
from . import meldinger as M

NT = 4
FACE_DOWN = -1
ACE, KING, QUEEN, JACK = 12, 11, 10, 9


@dataclass(frozen=True)
class SvaerParams:
    """Every [valgt] number of strategy §6, Ruby's Esmakker::Svaer::Params."""

    # §6.2 hand estimate
    makker_stik: F = F(7, 2)       # stik counted for makker (measured: 3½; katten 0)
    long_ak_bonus: F = F(1, 2)     # per card over 4 in a side suit with E K (suit trump)
    nt_long_bonus: F = F(1)        # per card over 4 in a suit with E K D (trumfløs)
    # §6.3 meldingsrunde
    nmax_margin: F = F(1, 2)       # Nmax: highest N with S >= N + margin
    gode_margin: F = F(1)          # S(klør) >= N + margin
    gode_close: F = F(1, 2)        # klør within this of the best trump
    vip_margin: F = F(1)           # every suit S >= N + margin
    vip_accept_margin: F = F(1, 2)  # take the turned card when S >= N + margin
    halve_min_length: int = 3      # cards in each side suit at halve
    p_width: F = F(2)              # P(hjem) = 1/2 + (S - N) / (2 * width), clamped
    expected_bet: F = F(1)         # stik short when it goes bet
    sol_p: tuple = (F(3, 4), F(3, 4), F(3, 4), F(3, 4))  # P(klaret) when the test passes
    # §6.4 trump
    nt_margin: F = F(1)            # trumfløs: S(NT) >= N + margin
    nt_close: F = F(1)             # and S(NT) >= S(best suit) - close
    # §6.5 good trumps
    good_trump_count: int = 5
    good_trump_honours: int = 2
    # §6.1 makker guess
    kitty_weight: F = F(3, 13)
    trump_lead_factor: F = F(4)
    overtake_factor: F = F(1, 4)
    # §6.7 sol
    sol_almost_low: int = 6        # a short suit is almost safe with c1 <= this
    sol_singleton_lead: int = 6    # lead a singleton at most this high
    sol_cover: int = 3             # defenders cover a sol lead this low
    sol_middle: int = 7            # the defenders' middle card
    sol_take: int = 10             # a dangerous card this high is worth taking a stik with
    sol_exchange_min: int = 10     # the sol exchange lays away only cards at least this high

    def __hash__(self):
        # the dataclass's own hash (of all the fields), worked out once: the
        # memos below key on the params, and hashing every Fraction field
        # on every lookup was a large part of Svær's time in search
        h = self.__dict__.get("_hash")
        if h is None:
            h = hash(tuple(getattr(self, f.name) for f in fields(self)))
            object.__setattr__(self, "_hash", h)
        return h


PARAMS = SvaerParams()


# -- cards -----------------------------------------------------------------

def suit(card):
    return card // 13 if 0 <= card < 52 else -1


def rank(card):
    return card % 13


def is_joker(card):
    return card >= 52


def ranks_in(hand, s):
    return sorted(rank(c) for c in hand if suit(c) == s)


def cards_in(hand, s):
    return sorted(c for c in hand if suit(c) == s)


def sol_value(card):
    """A card's height at a sol-melding: es 1, 2 … K 13."""
    r = rank(card)
    return 1 if r == ACE else r + 2


def num(value):
    """An estimate for the thought: an int when whole, else a float."""
    if value is None:
        return None
    value = F(value)
    return int(value) if value.denominator == 1 else float(value)


# -- what the seat knows ---------------------------------------------------

class Knowledge:
    """The seat's observation in the form both Svær implementations read
    (Ruby builds the same from Round#view_for)."""

    __slots__ = ("seat", "phase", "hand", "rules", "melding", "bids", "can_selv", "can_med", "can_pas",
                 "kind", "melder", "trump", "called", "esmakker", "selvmakker", "turned", "vip_card", "banks",
                 "discard_size", "discarded", "fordaekt_card", "fordaekt_waiting", "fordaekt_options",
                 "tricks", "trick", "tricks_won", "legal", "players", "most_stik", "vaeltet", "open_hand",
                 "can_turn", "can_accept", "aces", "trumps", "kitty_cards")

    @classmethod
    def from_obs(cls, obs):
        k = cls()
        seat = obs["seat"]
        legal = obs["legal_actions"]
        k.seat = seat
        k.phase = obs["phase"]
        k.hand = sorted(obs["hand"])
        k.rules = obs["rules"]
        k.melding = obs["melding"]
        k.bids = [a - A.BID for a in legal if a < A.PAS]
        k.can_selv = A.SELV in legal
        k.can_med = A.MED in legal
        k.can_pas = A.PAS in legal
        k.trumps = [a - A.TRUMP for a in legal if A.TRUMP <= a < A.ACE]
        k.aces = [a - A.ACE for a in legal if A.ACE <= a < A.VEND]
        k.can_turn = A.VEND in legal
        k.can_accept = A.ACCEPTER in legal
        k.kind = None if obs["melder"] is None else ("sol" if M.is_sol(obs["melding"]) else "stik")
        k.melder = obs["melder"]
        k.trump = obs["trump"]
        k.called = obs["called_ace"]
        k.esmakker = obs["esmakker"]
        k.selvmakker = bool(obs["selvmakker"])
        k.turned = list(obs["turned"])
        k.vip_card = obs["vip_card"]
        k.banks = len(obs["banks"])
        k.discard_size = obs["discard_size"]
        k.kitty_cards = sorted(obs["kitty_cards"])
        k.discarded = sorted(obs["discarded"]) if k.kind == "stik" else []
        fd = obs["fordaekt"]
        k.fordaekt_card = fd["card"] if fd and fd["card"] != FACE_DOWN else None
        k.fordaekt_waiting = bool(fd and fd["waiting"])
        k.fordaekt_options = sorted(a - A.FORDAEKT for a in legal if a >= A.FORDAEKT and a < A.ACTION_COUNT)

        def norm(plays):
            out = []
            for s, card in plays:
                if s == k.melder and k.fordaekt_card is not None and card == k.fordaekt_card:
                    card = FACE_DOWN
                out.append((s, card))
            return out

        k.tricks = [(leader, norm(plays), winner) for leader, plays, winner in obs["tricks"]]
        k.trick = norm(obs["trick"])
        k.tricks_won = list(obs["tricks_won"])
        k.legal = sorted(a - A.PLAY for a in legal if A.PLAY <= a < A.FORDAEKT)
        k.players = list(obs["players"])
        k.most_stik = obs["most_stik"]
        k.vaeltet = list(obs["vaeltet"])
        k.open_hand = sorted(obs["open_hand"]) if obs["open_hand"] is not None else None
        return k

    @classmethod
    def from_round(cls, r, seat):
        """from_obs(observe(r, seat)), read straight off the engine's Round
        with the same visibility rules (tests/test_svaer.py checks they are
        equal), without building the observation dict: self-play asks Svær
        hundreds of thousands of times. The finished stik as the seat sees
        them are cached per stik (_seen_tricks)."""
        k = cls()
        legal = r.legal_actions(seat)
        melder = r.melder
        melding = r.melding
        k.seat = seat
        k.phase = r.phase
        k.hand = C.cards_of(r.hands[seat])
        k.rules = r.rules
        k.melding = melding
        k.discard_size = r.discard_size(seat)
        k.trump = r.trump
        k.called = r.called_ace
        k.melder = melder
        if r.phase == "bidding":
            k.bids = [a - A.BID for a in legal if a < A.PAS]
            k.can_selv = A.SELV in legal
            k.can_med = A.MED in legal
            k.can_pas = A.PAS in legal
            k.trumps = k.aces = k.legal = k.fordaekt_options = []
            k.can_turn = k.can_accept = False
        else:
            k.bids = [a - A.BID for a in legal if a < A.PAS]
            k.can_selv = k.can_med = k.can_pas = False
            k.trumps = [a - A.TRUMP for a in legal if A.TRUMP <= a < A.ACE]
            k.aces = [a - A.ACE for a in legal if A.ACE <= a < A.VEND]
            k.can_turn = A.VEND in legal
            k.can_accept = A.ACCEPTER in legal
            k.legal = sorted(a - A.PLAY for a in legal if A.PLAY <= a < A.FORDAEKT)
            k.fordaekt_options = sorted(a - A.FORDAEKT for a in legal if A.FORDAEKT <= a < A.ACTION_COUNT)
        kind = None if melder is None else ("sol" if M.is_sol(melding) else "stik")
        k.kind = kind
        known = r.esmakker_known(seat)
        k.esmakker = r.esmakker if known else None
        k.selvmakker = bool(known and r.selvmakker())
        k.turned = list(r.turned_cards())
        k.vip_card = r.vip_card
        k.banks = len(r.banks)
        took = False
        k.discarded = []
        if r.kind == "stik":
            took = r.kitty_taken and seat == r.declarer()
            if kind == "stik" and r.discarded and seat == r.declarer():
                k.discarded = sorted(r.discarded)
        elif r.kind == "sol":
            took = True
        k.kitty_cards = sorted(r.kitty_seen[seat]) if took and not r.tricks else []
        fd = r.fordaekt
        k.fordaekt_card = fd if fd is not None and seat == melder else None
        k.fordaekt_waiting = fd is not None and not r.fordaekt_played
        k.tricks = _seen_tricks(r, seat, k.fordaekt_card)
        k.trick = _seen_plays(r.trick, seat, melder, k.fordaekt_card)
        k.tricks_won = list(r.tricks_won)
        k.players = list(r.players)
        sol = r.kind == "sol"
        k.most_stik = M.MOST_STIK[melding] if sol else None
        k.vaeltet = list(r.vaeltet()) if sol else []
        k.open_hand = C.cards_of(r.hands[melder]) if sol and melding in M.OPEN_HAND and r.tricks else None
        return k


def _seen_plays(plays, seat, melder, fordaekt_card):
    """A stik's plays as Knowledge holds them: (seat, card), the fordækt
    card FACE_DOWN (observe hides it from all but the melder; from_obs's
    norm hides it from the melder too)."""
    out = []
    for play in plays:
        s, card = play[0], play[1]
        if (play[4] and seat != melder) or (s == melder and fordaekt_card is not None and card == fordaekt_card):
            card = FACE_DOWN
        out.append((s, card))
    return out


_SEEN_TRICKS = {}


def _seen_tricks(r, seat, fordaekt_card):
    """Knowledge.tricks for the seat: [(leader, plays, winner)]. A finished
    stik is a tuple made once by the Round that plays it and shared by its
    clones (search rollouts), which have the same stik before it and the
    same melder and fordækt card: the list up to a stik is cached on that
    tuple, per seat, and a new stik adds its own to the list of the one
    before. The lists are shared, so nothing may change them (Svær only
    reads them). The entry keeps the tuple, so its id is not reused."""
    tricks = r.tricks
    n = len(tricks)
    if not n:
        return []
    key = (id(tricks[-1]), seat)
    entry = _SEEN_TRICKS.get(key)
    if entry is not None and entry[0] is tricks[-1]:
        return entry[1]
    i = n - 1
    seen = []
    while i:
        entry = _SEEN_TRICKS.get((id(tricks[i - 1]), seat))
        if entry is not None and entry[0] is tricks[i - 1]:
            seen = entry[1]
            break
        i -= 1
    if len(_SEEN_TRICKS) > 400_000:
        _SEEN_TRICKS.clear()
    melder = r.melder
    for j in range(i, n):
        leader, plays, winner = tricks[j]
        seen = seen + [(leader, _seen_plays(plays, seat, melder, fordaekt_card), winner)]
        _SEEN_TRICKS[(id(tricks[j]), seat)] = (tricks[j], seen)
    return seen


# -- §6.2 hand estimate ------------------------------------------------------

def quick_tricks(ranks):
    have = set(ranks)
    if ACE in have:
        if KING in have and QUEEN in have:
            return F(3)
        if KING in have:
            return F(2)
        if QUEEN in have:
            return F(3, 2)
        return F(1)
    if KING in have:
        if QUEEN in have:
            return F(1)
        return F(1, 2) if len(ranks) >= 2 else F(0)
    return F(0)


def trump_stik(ranks):
    have = set(ranks)
    length = len(ranks)
    value = F(0)
    if ACE in have:
        value += 1
    if KING in have and length >= 2:
        value += 1
    if QUEEN in have and length >= 3:
        value += 1
    return value + max(0, length - 3)


def called_stik(ranks):
    have = set(ranks)
    if KING in have and QUEEN in have:
        return F(3, 2)
    if KING in have and len(ranks) >= 2:
        return F(1)
    return F(0)


def own_stik(hand, trump, called, p=PARAMS):
    """The stik the hand takes itself with `trump` (0-3, NT), the makker
    holding the ace of `called` (§6.2)."""
    masks, jokers = suit_masks(hand)
    return _own_stik(masks, jokers, trump, called, p)


# A suit's part of own_stik by its role: trumfløs, trump, the called suit, a side suit
_NT_ROLE, _TRUMP_ROLE, _CALLED_ROLE, _SIDE_ROLE = 0, 1, 2, 3


def _own_stik(masks, jokers, trump, called, p):
    total = F(jokers)
    for s in range(4):
        if trump == NT:
            role = _NT_ROLE
        elif s == trump:
            role = _TRUMP_ROLE
        elif s == called:
            role = _CALLED_ROLE
        else:
            role = _SIDE_ROLE
        total += suit_stik(masks[s], role, p)
    return total


def suit_masks(hand):
    """The hand's ranks per suit as 13-bit masks (bit r: rank r), and how
    many jokers it holds."""
    masks = [0, 0, 0, 0]
    jokers = 0
    for c in hand:
        if c >= 52:
            jokers += 1
        elif c >= 0:
            masks[c // 13] |= 1 << (c % 13)
    return masks, jokers


def mask_ranks(mask):
    """A suit mask's ranks, lowest first (as ranks_in)."""
    return [r for r in range(13) if mask >> r & 1]


_SUIT_STIK = {}


def suit_stik(mask, role, p=PARAMS):
    """One suit's stik in own_stik (§6.2), memoized: a pure function of the
    suit's ranks, its role and the params (8192 patterns per role)."""
    key = (mask, role, p)
    value = _SUIT_STIK.get(key)
    if value is None:
        rs = mask_ranks(mask)
        length = len(rs)
        if role == _NT_ROLE:
            value = quick_tricks(rs)
            if length > 4 and ACE in rs and KING in rs and QUEEN in rs:
                value += p.nt_long_bonus * (length - 4)
        elif role == _TRUMP_ROLE:
            value = trump_stik(rs)
        elif role == _CALLED_ROLE:
            value = called_stik(rs)
        else:
            value = quick_tricks(rs)
            if length > 4 and ACE in rs and KING in rs:
                value += p.long_ak_bonus * (length - 4)
        if len(_SUIT_STIK) > _MEMO_SIZE:
            _SUIT_STIK.clear()
        _SUIT_STIK[key] = value
    return value


def call_choice(hand, trump, callable_suits):
    """§6.4: among the aces it may call, not trump, the shortest suit; on a
    tie the one where it holds the highest card, then the lowest suit."""
    return _call_choice(suit_masks(hand)[0], trump, callable_suits)


def _call_choice(masks, trump, callable_suits):
    options = [s for s in callable_suits if s != trump] or list(callable_suits)

    def key(s):
        m = masks[s]
        return (m.bit_count(), -(m.bit_length() - 1 if m else -1), s)

    return min(options, key=key)


def free_aces(hand):
    free = [s for s in range(4) if C.ace(s) not in hand]
    return free or [0, 1, 2, 3]


def _free_aces(masks):
    free = [s for s in range(4) if not masks[s] >> ACE & 1]
    return free or [0, 1, 2, 3]


# Memos: the estimates and tests below are pure functions of the hand and
# the params, and search asks them again and again for the same hands (every
# sampled world replays the bids); the Fraction arithmetic is the cost.
_MEMO_SIZE = 200_000
_ESTIMATES = {}


def estimates(hand, p=PARAMS, called=None):
    """S per trump 0-4: own stik plus makker's; the called suit as §6.4
    would call it for that trump, unless it is already called."""
    key = (tuple(hand), p, called)
    out = _ESTIMATES.get(key)
    if out is None:
        if len(_ESTIMATES) > _MEMO_SIZE:
            _ESTIMATES.clear()
        masks, jokers = suit_masks(hand)
        free = _free_aces(masks)
        out = []
        for t in range(5):
            c = called if called is not None else _call_choice(masks, t, free)
            out.append(_own_stik(masks, jokers, t, c, p) + p.makker_stik)
        out = _ESTIMATES[key] = tuple(out)
    return list(out)


def own_estimates(hand, p=PARAMS, called=None):
    return [s - p.makker_stik for s in estimates(hand, p, called)]


def best_suit(values):
    best = 0
    for t in range(1, 4):
        if values[t] > values[best]:
            best = t
    return best


@lru_cache(maxsize=4096)
def nmax(s_best, p=PARAMS):
    """The highest stik melding Svær goes to, or None (§6.3)."""
    top = None
    for n in M.NUMBERS:
        if s_best >= n + p.nmax_margin:
            top = n
    if top is None and s_best >= 8:
        top = 8
    return top


# -- §6.7 sol test -----------------------------------------------------------

SAFE, ALMOST, DANGER = 2, 1, 0


def _safe(values):
    if not values:
        return True
    if any(v > 2 * i + 1 for i, v in enumerate(values)):
        return False
    return len(values) < 4 or values[0] == 1


def suit_level(values, p=PARAMS):
    values = sorted(values)
    if _safe(values):
        return SAFE
    if len(values) <= 2 and values[0] <= p.sol_almost_low:
        return ALMOST
    if len(values) >= 3 and _safe(values[:-1]):
        return ALMOST
    return DANGER


def sol_values(hand, s):
    return sorted(sol_value(c) for c in hand if suit(c) == s)


_SOL_PASSES = {}


def sol_passes(melding, hand, p=PARAMS):
    key = (melding, tuple(hand), p)
    passed = _SOL_PASSES.get(key)
    if passed is None:
        if len(_SOL_PASSES) > _MEMO_SIZE:
            _SOL_PASSES.clear()
        passed = _SOL_PASSES[key] = _sol_passes(melding, hand, p)
    return passed


_SOL_LEVELS = {}


def _sol_level(mask, p):
    """suit_level of a suit given as a rank mask (memoized)."""
    key = (mask, p)
    level = _SOL_LEVELS.get(key)
    if level is None:
        level = _SOL_LEVELS[key] = suit_level([1 if r == ACE else r + 2 for r in mask_ranks(mask)], p)
    return level


def _sol_passes(melding, hand, p):
    masks = suit_masks(hand)[0]
    levels = [_sol_level(m, p) for m in masks]
    lengths = [m.bit_count() for m in masks]
    danger = [s for s in range(4) if levels[s] == DANGER]
    almost = [s for s in range(4) if levels[s] == ALMOST]
    if melding == M.REN_BORDLAEGGER:
        return not danger and not almost
    if melding == M.BORDLAEGGER:
        unsafe = danger + almost
        return len(unsafe) == 0 or (len(unsafe) == 1 and lengths[unsafe[0]] == 1)
    if melding == M.REN_SOL:
        return not danger and len(almost) <= 1
    if melding == M.SOL:
        return not danger or (len(danger) == 1 and lengths[danger[0]] <= 2)
    return False


# -- §6.3 expected value -------------------------------------------------------

@lru_cache(maxsize=4096)
def p_hjem(s, n, p=PARAMS):
    value = F(1, 2) + (s - n) / (2 * p.p_width)
    return min(F(1), max(F(0), value))


def stik_factor(melding, trump, points, vip_card=None, banks=0):
    pa = M.pahaeng(melding)
    factor = F(1)
    if pa in (M.GODE, M.HALVE):
        factor *= points.pahaeng
    if pa == M.VIP:
        factor *= (points.vip_first, points.vip_second, points.vip_third)[(vip_card or 1) - 1]
    if trump == NT:
        factor *= points.trumflos
    if pa in (M.VIP, M.HALVE) and trump == 0:
        factor *= points.klor
    return factor * points.bank ** banks


_STIK_VALUES = {}


def stik_value(melding, s, trump, points, p=PARAMS, vip_card=None, banks=0):
    """P(hjem) × gain − P(bet) × loss for the melder's side, per seat.
    Memoized; Points holds a dict, so it is keyed by identity and the entry
    keeps it (its id is not reused while cached)."""
    key = (melding, s, trump, id(points), p, vip_card, banks)
    entry = _STIK_VALUES.get(key)
    if entry is None or entry[0] is not points:
        if len(_STIK_VALUES) > _MEMO_SIZE:
            _STIK_VALUES.clear()
        entry = _STIK_VALUES[key] = (points, _stik_value(melding, s, trump, points, p, vip_card, banks))
    return entry[1]


def _stik_value(melding, s, trump, points, p, vip_card, banks):
    n = M.number(melding)
    stake = points.stake(n)
    factor = stik_factor(melding, trump, points, vip_card, banks)
    over = max(0, math.floor(s) - n)
    chance = p_hjem(s, n, p)
    return chance * (stake + over) * factor - (1 - chance) * stake * p.expected_bet * factor


def sol_ev(melding, points, p=PARAMS):
    amount = points.sol_amount(M.SOL_KINDS[melding - M.SOL]) * 3
    chance = p.sol_p[melding - M.SOL]
    return chance * amount - (1 - chance) * amount


# -- the bot -------------------------------------------------------------------

class Svaer:
    """Svær on an observation. `act(obs)` gives the action (None in the bank
    window: it never banks); `decide(obs)` the action and its thought."""

    def __init__(self, seed=None, params=PARAMS):
        self.p = params

    def act(self, obs):
        # only the action: the thought's expectations ("Vis kort") are not
        # worked out (they decide nothing, and cost as much as the play)
        return decide(Knowledge.from_obs(obs), self.p, explain=False)[0]

    def act_round(self, r, seat):
        """act(observe(r, seat)) without the observation dict
        (Knowledge.from_round): what self-play calls."""
        return decide(Knowledge.from_round(r, seat), self.p, explain=False)[0]

    def decide(self, obs):
        k = Knowledge.from_obs(obs)
        action, thought = decide(k, self.p)
        return action, thought

    def decide_out_of_turn(self, obs):
        """Out of turn (Ruby Svaer#decide_out_of_turn): as melder before a
        forhånd who is someone else leads, it lays fordækt by §6.4 as on its
        own turn: always when it may, `fordaekt_card`. (action, thought), or
        (None, None) when it does not."""
        if obs["to_act"] == obs["seat"]:
            return None, None
        k = Knowledge.from_obs(obs)
        if not k.fordaekt_options:
            return None, None
        card = fordaekt_card(k)
        if card is None:
            return None, None
        return A.FORDAEKT + card, thought("lay_fordaekt", "fordaekt", None, play_expect(k, self.p))

    def offer_fordaekt(self, obs):
        """Fordækt out of turn for self-play (selfplay.ask_fordaekt)."""
        return self.decide_out_of_turn(obs)[0]


def thought(decision, reason, melding=None, expect=None):
    return {"decision": decision, "reason": reason, "melding": None if melding is None else M.CODES[melding],
            "expect": expect or no_expect()}


def no_expect(melding=None):
    return {"melding": None if melding is None else M.CODES[melding], "stik": {"self": None, "makker": None},
            "makker": None, "points": None}


def decide(k, p=PARAMS, explain=True):
    """(action, thought) for the seat to act, or (None, None). Without
    `explain`, a play's thought leaves out what Svær expects (play_expect);
    the action is the same."""
    phase = k.phase
    if phase == "banking":
        return None, None
    if phase == "bidding":
        if not k.bids and not k.can_pas:
            return None, None
        return bid(k, p)
    if phase == "choosing_trump" and k.trumps:
        return choose_trump(k, p)
    if phase == "calling_ace" and k.aces:
        return call_ace(k, p)
    if phase == "turning" and (k.can_turn or k.can_accept):
        return turn(k, p)
    if phase in ("discarding", "exchanging") and k.discard_size:
        return discard(k, p)
    if phase == "playing" and (k.legal or k.fordaekt_options):
        return play(k, p, explain)
    return None, None


# -- bidding ---------------------------------------------------------------------

def candidate_value(k, melding, values, p):
    """The risk-weighted value of bidding `melding`, or None when Svær is
    not willing to (§6.3)."""
    hand = k.hand
    return _candidate_value(melding, values, k.rules.points, p, lambda: halve_shape(hand, values, p),
                            lambda: sol_passes(melding, hand, p))


_CANDIDATE_TABLES = {}


def candidate_values(hand, values, points, p):
    """candidate_value for every melding (a tuple by melding id), for a
    hand with the estimates `values`. All that it reads of the hand is its
    estimates, whether it has the halve shape and which sol tests it passes,
    so the table is memoized on those: many hands share them. Points holds
    a dict, so it is keyed by identity and the entry keeps it."""
    halve_ok = halve_shape(hand, values, p)
    sol_ok = tuple(sol_passes(m, hand, p) for m in range(M.SOL, M.COUNT))
    key = (tuple(values), halve_ok, sol_ok, id(points), p)
    entry = _CANDIDATE_TABLES.get(key)
    if entry is None or entry[0] is not points:
        if len(_CANDIDATE_TABLES) > _MEMO_SIZE:
            _CANDIDATE_TABLES.clear()
        table = tuple(_candidate_value(m, values, points, p, lambda: halve_ok, lambda m=m: sol_ok[m - M.SOL])
                      for m in range(M.COUNT))
        entry = _CANDIDATE_TABLES[key] = (points, table)
    return entry[1]


def _candidate_value(melding, values, points, p, halve_ok, sol_ok):
    """candidate_value with the hand's tests as callables: halve_ok() the
    halve shape, sol_ok() the sol test for this melding."""
    if M.is_sol(melding):
        return sol_ev(melding, points, p) if sol_ok() else None
    n = M.number(melding)
    pa = M.pahaeng(melding)
    s_best = max(values)
    top = nmax(s_best, p)
    if pa == M.NONE:
        if top is None or n > top:
            return None
        best = 0
        for t in range(1, 5):
            if values[t] > values[best]:
                best = t
        return stik_value(melding, values[best], best, points, p)
    if pa == M.GODE:
        if values[0] >= n + p.gode_margin and values[0] >= s_best - p.gode_close:
            return stik_value(melding, values[0], 0, points, p)
        return None
    if pa == M.HALVE:
        if top is None or n > top or values[NT] < n or not halve_ok():
            return None
        t = best_suit(values)
        return stik_value(melding, values[t], t, points, p)
    if pa == M.VIP:
        if all(values[t] >= n + p.vip_margin for t in range(4)) and values[NT] >= n:
            return stik_value(melding, min(values[:4]), 1, points, p)
        return None
    return None


_HONOURS = 1 << ACE | 1 << KING | 1 << QUEEN


def halve_shape(hand, values, p):
    masks = suit_masks(hand)[0]
    called = _call_choice(masks, best_suit(values), _free_aces(masks))
    for s in range(4):
        m = masks[s]
        if not m:
            return False
        if s == called:
            continue
        if m.bit_count() < p.halve_min_length or not m & _HONOURS:
            return False
    return True


def bid(k, p):
    values = estimates(k.hand, p)
    table = candidate_values(k.hand, values, k.rules.points, p)
    own = max(values) - p.makker_stik
    current = k.melding

    def expect(melding, value):
        sol = melding is not None and M.is_sol(melding)
        e = no_expect(melding)
        if melding is not None and not sol:
            e["stik"] = {"self": num(own), "makker": num(p.makker_stik)}
        e["points"] = num(value)
        return e

    if k.can_med and current is not None and M.is_sol(current) and sol_passes(current, k.hand, p):
        value = sol_ev(current, k.rules.points, p)
        return A.MED, thought("gaa_med", "sol_test", current, expect(current, value))
    if k.can_selv and current is not None:
        value = table[current]
        if value is not None and value > 0:
            return A.SELV, thought("det_kan_jeg_selv", "within_reach", current, expect(current, value))
    best = None
    for melding in k.bids:
        value = table[melding]
        if value is not None and value > 0 and (best is None or value > best[1]):
            best = (melding, value)
    if best is not None:
        melding, value = best
        pa = M.pahaeng(melding)
        reason = "sol_test" if M.is_sol(melding) else ("bid_" + ("lowest", "gode", "halve", "vip")[pa])
        return A.BID + melding, thought("bid", reason, melding, expect(melding, value))
    reason = "pas_weak" if nmax(max(values), p) is None else "pas_too_high"
    return A.PAS, thought("pas", reason, None, no_expect())


# -- declaring ---------------------------------------------------------------------

def play_expect(k, p, trump=None, called=None):
    """What Svær expects of a stik melding's runde once it is played."""
    trump = k.trump if trump is None else trump
    called = k.called if called is None else called
    e = no_expect(k.melding)
    if k.kind == "sol":
        e["stik"]["self"] = k.tricks_won[k.seat]
        return e
    if trump is None:
        values = own_estimates(k.hand, p, called)
        own = max(values)
    else:
        own = own_stik(k.hand, trump, called, p)
    mine = k.tricks_won[k.seat] + own
    e["stik"]["self"] = num(mine)
    e["makker"] = guessed_partner(k, p)
    if k.seat == k.melder:
        makker = F(0) if k.selvmakker else p.makker_stik
        e["stik"]["makker"] = num(makker)
        if trump is not None:
            total = mine + makker + (k.tricks_won[k.esmakker] if k.esmakker is not None and k.esmakker != k.seat else 0)
            e["points"] = num(stik_value(k.melding, total, trump, k.rules.points, p, k.vip_card, k.banks))
    return e


def choose_trump(k, p):
    called = k.called
    values = estimates(k.hand, p, called)
    options = k.trumps
    best = None
    for t in options:
        if t == NT:
            continue
        if best is None or values[t] > values[best]:
            best = t
    if NT in options and k.melding is not None:
        n = M.number(k.melding)
        if values[NT] >= n + p.nt_margin and values[NT] >= values[best] - p.nt_close:
            return A.TRUMP + NT, thought("choose_trump", "trumfloes", None, play_expect(k, p, NT, called))
    return A.TRUMP + best, thought("choose_trump", "best_trump", None, play_expect(k, p, best, called))


def call_ace(k, p):
    trump = k.trump
    if trump is None:
        trump = best_suit(estimates(k.hand, p))
    s = call_choice(k.hand, trump, k.aces)
    return A.ACE + s, thought("call_ace", "call_shortest", None, play_expect(k, p, k.trump, s))


def turn(k, p):
    if k.can_accept and k.turned:
        card = k.turned[-1]
        t = NT if is_joker(card) else suit(card)
        value = own_stik(k.hand, t, k.called, p) + p.makker_stik
        if value >= M.number(k.melding) + p.vip_accept_margin or not k.can_turn:
            return A.ACCEPTER, thought("accept_trump", "vip_accept", None, play_expect(k, p, t))
    return A.VEND, thought("turn_card", "vip_turn", None, play_expect(k, p))


def own_cards(k):
    """The seat's own cards when it lays away: its hand, as the kitty is
    taken up only after the discard (REGLER §2.0; at a sol-melding each
    seat likewise)."""
    return list(k.hand)


def discard(k, p):
    own = own_cards(k)
    if k.kind == "sol":
        cards = sol_discard(own, k.discard_size, p)
        return tuple(sorted(cards)), thought("discard", "sol_discard", None, play_expect(k, p))
    cards, reason = stik_discard(own, k.trump, k.called)
    rest = [c for c in own if c not in cards]
    e = play_expect(k, p)
    e["stik"]["self"] = num(k.tricks_won[k.seat] + own_stik(rest, k.trump, k.called, p))
    return tuple(sorted(cards)), thought("discard", reason, None, e)


def stik_discard(hand, trump, called):
    """Three cards to lay away from the 16 (§6.4 "Katten")."""
    def protected(c):
        return is_joker(c) or suit(c) == trump or rank(c) == ACE or (suit(c) == called and rank(c) == KING)

    chosen = []
    reason = "discard_low"
    trumps = sum(1 for c in hand if suit(c) == trump) if trump != NT else 0
    if trump != NT and trumps >= 4:
        side = [s for s in range(4) if s not in (trump, called) and any(not protected(c) for c in cards_in(hand, s))]
        if side:
            s = min(side, key=lambda s: (len(cards_in(hand, s)), s))
            for c in cards_in(hand, s):
                if not protected(c) and len(chosen) < 3:
                    chosen.append(c)
            reason = "discard_void"
    while len(chosen) < 3:
        rest = [c for c in hand if c not in chosen]
        options = [s for s in range(4) if s != trump and s != called and any(not protected(c) for c in cards_in(rest, s))]
        if not options:
            options = [s for s in range(4) if s != trump and any(not protected(c) for c in cards_in(rest, s))]
        if not options:
            break
        s = min(options, key=lambda s: (quick_tricks(ranks_in(rest, s)), len(cards_in(rest, s)), s))
        chosen.append(next(c for c in cards_in(rest, s) if not protected(c)))
    while len(chosen) < 3:
        rest = [c for c in hand if c not in chosen]
        chosen.append(min(rest, key=lambda c: (is_joker(c), suit(c) == trump, rank(c) == ACE, rank(c), c)))
    return chosen, reason


def sol_discard(hand, size, p):
    """§6.7 "Katten ved sol": the highest cards of the worst, shortest
    suits, at most as many as the kitty holds, and only those at least
    sol_exchange_min high (it takes as many up)."""
    chosen = []
    while len(chosen) < size:
        rest = [c for c in hand if c not in chosen]
        plain = [c for c in rest if not is_joker(c)]
        if not plain:
            chosen.append(min(rest))
            continue
        options = sorted({suit(c) for c in plain})

        def key(s):
            values = sol_values(rest, s)
            return (suit_level(values, p), len(values), -values[-1], s)

        s = min(options, key=key)
        chosen.append(max(cards_in(rest, s), key=sol_value))
    return [c for c in chosen if not is_joker(c) and sol_value(c) >= p.sol_exchange_min]


# -- the play: what the seat has seen ----------------------------------------------

class Table:
    """What Svær works out from the stik played: who is void where, who
    discarded what, the cards not yet seen, the makker weights."""

    def __init__(self, k, p):
        self.k = k
        self.p = p
        trump = k.trump if k.kind == "stik" else None
        self.trump = trump
        self.void = [[False] * 4 for _ in range(4)]
        self.discards = [[] for _ in range(4)]
        self.led = [[] for _ in range(4)]
        self.played = set()
        self.weights = self._initial_weights()
        self.ace_fallen = False
        self._called_ace = C.ace(k.called) if k.called is not None else None
        self._highest = None
        for leader, plays, winner in k.tricks:
            self._read(plays)
        self._read(k.trick)
        seen = set(k.hand) | self.played | set(k.discarded)
        if k.fordaekt_card is not None:
            seen.add(k.fordaekt_card)
        self.unseen = set(range(C.DECK_SIZE)) - seen

    def _initial_weights(self):
        k = self.k
        if k.kind != "stik" or k.esmakker is not None or k.selvmakker:
            return None
        if k.seat == k.melder:
            seats = [s for s in range(4) if s != k.seat]
        else:
            seats = [s for s in range(4) if s not in (k.seat, k.melder)]
        weights = {s: F(1) for s in seats}
        weights["kitty"] = self.p.kitty_weight
        return weights

    def suit_of(self, card):
        return self.k.called if card == FACE_DOWN else suit(card)

    def rank_of(self, card):
        return -1 if card == FACE_DOWN else rank(card)

    def _read(self, plays):
        k = self.k
        if not plays:
            return
        led = self.suit_of(plays[0][1]) if not (plays[0][1] >= 52) else -1
        partial = []
        known = None  # the winner of `partial` when worked out already (pure: the same as winner(partial))
        for index, (seat, card) in enumerate(plays):
            s = self.suit_of(card)
            if card != FACE_DOWN:
                self.played.add(card)
            if card == self._called_ace:
                self.ace_fallen = True
            if index == 0:
                if s >= 0:
                    self.led[seat].append(s)
            elif led >= 0 and s != led and not (card != FACE_DOWN and is_joker(card)):
                self.void[seat][led] = True
                if s != self.trump:
                    self.discards[seat].append(s)
            if self.weights is not None and seat in self.weights:
                if led == k.called and index > 0 and s != led and not (card != FACE_DOWN and is_joker(card)):
                    self.weights[seat] = F(0)
                if index == 0 and seat != k.melder and self.trump is not None and self.trump != NT and s == self.trump:
                    self.weights[seat] *= self.p.trump_lead_factor
                before = (known[1] if known is not None and known[0] == index else self.winner(partial)) if partial else None
                after = self.winner(partial + [(seat, card)])
                known = (index + 1, after)
                if before == k.melder and after == seat:
                    self.weights[seat] *= self.p.overtake_factor
            partial.append((seat, card))

    def winner(self, plays):
        """Who takes the stik so far (Trick#winner on a partial stik)."""
        trump = self.trump
        lead_seat, lead = plays[0]
        trumps = [(s, c) for s, c in plays if trump is not None and trump != NT and c != FACE_DOWN and suit(c) == trump]
        if lead != FACE_DOWN and is_joker(lead) and (not trumps or not self.k.rules.joker_trumpable):
            return lead_seat
        if trumps:
            return max(trumps, key=lambda sc: rank(sc[1]))[0]
        led = self.suit_of(lead)
        pool = [(s, c) for s, c in plays if (c == FACE_DOWN or not is_joker(c)) and self.suit_of(c) == led]
        return max(pool, key=lambda sc: self.rank_of(sc[1]))[0]

    def highest_out(self, s):
        # the highest rank not seen, per suit, worked out once (unseen is fixed)
        highest = self._highest
        if highest is None:
            highest = self._highest = {}
            for c in self.unseen:
                cs, r = suit(c), rank(c)
                if r > highest.get(cs, -1):
                    highest[cs] = r
        return highest.get(s, -1)

    def sure(self, card):
        return not is_joker(card) and rank(card) > self.highest_out(suit(card))

    def trumps_out(self):
        return self.trump is not None and self.trump != NT and any(suit(c) == self.trump for c in self.unseen)


def partner(k, table):
    """The seat Svær knows is its partner this runde, or None."""
    if k.kind != "stik":
        return None
    if k.seat == k.melder:
        return k.esmakker if k.esmakker is not None and k.esmakker != k.seat else None
    if k.esmakker == k.seat:
        return k.melder
    if k.esmakker is not None or k.selvmakker:
        if k.selvmakker:
            return None
        return next(s for s in range(4) if s not in (k.seat, k.melder, k.esmakker))
    return None


def makker_guess(table):
    """The seat with the highest weight (clockwise from Svær on a tie)."""
    weights = table.weights
    if not weights:
        return None
    k = table.k
    best = None
    for offset in (1, 2, 3):
        s = (k.seat + offset) % 4
        if s in weights and weights[s] > 0 and (best is None or weights[s] > weights[best]):
            best = s
    return best


def guessed_partner(k, p):
    """expect.makker: the seat Svær takes for its partner."""
    if k.kind != "stik":
        return None
    if k.called is None and k.seat != k.melder:
        return None
    table = Table(k, p)
    known = partner(k, table)
    if known is not None or k.selvmakker:
        return known
    if k.esmakker == k.seat:
        return k.melder
    guess = makker_guess(table)
    if k.seat == k.melder or guess is None:
        return guess
    return next(s for s in range(4) if s not in (k.seat, k.melder, guess))


def opponents(k, table):
    mate = partner(k, table)
    return [s for s in range(4) if s != k.seat and s != mate]


def opps_may_trump(k, table):
    if not table.trumps_out():
        return False
    return any(not table.void[o][table.trump] for o in opponents(k, table))


# -- the play -----------------------------------------------------------------------

def play(k, p, explain=True):
    if k.kind == "sol":
        card, reason = sol_play(k, p)
        return A.PLAY + card, thought("play", reason, None, play_expect(k, p) if explain else None)
    table = Table(k, p)
    if k.fordaekt_options:
        card = fordaekt_card(k)
        if card is not None:
            return A.FORDAEKT + card, thought("lay_fordaekt", "fordaekt", None, play_expect(k, p) if explain else None)
    if not k.trick:
        card, reason = lead(k, table, p)
    else:
        card, reason = follow(k, table, p)
    return A.PLAY + card, thought("play", reason, None, play_expect(k, p) if explain else None)


def fordaekt_card(k):
    """§6.4: the lowest card of the weakest side suit, never trump or joker."""
    options = [s for s in range(4) if s != k.trump and cards_in(k.hand, s)]
    if not options:
        return None
    s = min(options, key=lambda s: (quick_tricks(ranks_in(k.hand, s)), len(cards_in(k.hand, s)), s))
    card = cards_in(k.hand, s)[0]
    return card if card in k.fordaekt_options else None


def is_fordaekt(k, card):
    return k.fordaekt_waiting and k.seat == k.melder and card == k.fordaekt_card


def trumps_in(k, table, cards):
    t = table.trump
    if t is None or t == NT:
        return []
    return [c for c in cards if suit(c) == t and not is_fordaekt(k, c)]


def first_lead(k):
    """Whether the seat leads the runde's first stik: it is "i forhånd"
    (§6.6; the forhånd leads the first stik at every melding, REGLER §2.0)."""
    return not k.tricks


def top_sequence_lead(cards):
    """§6.6: the highest of a top sequence, the highest of a weak suit,
    otherwise the lowest."""
    ordered = sorted(cards, key=rank, reverse=True)
    if len(ordered) >= 2 and rank(ordered[0]) - rank(ordered[1]) == 1 and rank(ordered[0]) >= JACK:
        return ordered[0]
    if rank(ordered[0]) < QUEEN:
        return ordered[0]
    return ordered[-1]


def lead(k, table, p):
    if k.seat == k.melder:
        return melder_lead(k, table, p)
    if k.esmakker == k.seat:
        return esmakker_lead(k, table, p)
    return defender_lead(k, table, p)


def side_cards(k, table, cards):
    t = table.trump
    return [c for c in cards if not is_joker(c) and (t is None or t == NT or suit(c) != t) and not is_fordaekt(k, c)]


def cash(k, table, cards, opps_trump):
    """A sure winner in a side suit: the highest, in the longest such suit."""
    winners = [c for c in side_cards(k, table, cards) if table.sure(c)]
    if opps_trump:
        winners = [c for c in winners if not any(table.void[o][suit(c)] for o in opponents(k, table))]
    if not winners:
        return None
    suits = sorted({suit(c) for c in winners}, key=lambda s: (-len(cards_in(cards, s)), s))
    return max((c for c in winners if suit(c) == suits[0]), key=rank)


def joker_lead(k, cards, opps_trump):
    jokers = [c for c in cards if is_joker(c)]
    if jokers and (not k.rules.joker_trumpable or not opps_trump):
        return jokers[0]
    return None


def signal_lead(k, table, cards):
    mate = partner(k, table)
    if mate is None or not table.discards[mate]:
        return None
    s = table.discards[mate][-1]
    mine = [c for c in side_cards(k, table, cards) if suit(c) == s]
    if not mine:
        return None
    if k.rules.afkast == "renonce":
        t = table.trump
        if t is None or t == NT or table.void[mate][t] or not table.trumps_out():
            return None
    return mine[0]


def long_lead(k, table, cards, shortest=False, avoid_bad=False):
    side = side_cards(k, table, cards)
    if not side:
        return None
    suits = sorted({suit(c) for c in side})
    if k.rules.afkast == "renonce" and opps_may_trump(k, table):
        safe = [s for s in suits if not any(s in table.discards[o] for o in opponents(k, table))]
        suits = safe or suits
    if avoid_bad:
        good = [s for s in suits if not bad_lead_suit(ranks_in(side, s))]
        suits = good or suits
    key = (lambda s: (len(cards_in(side, s)), s)) if shortest else (lambda s: (-len(cards_in(side, s)), s))
    s = min(suits, key=key)
    return top_sequence_lead(cards_in(side, s))


def bad_lead_suit(ranks):
    """§6.6: not from a bare king at the top or a tenace (E D, K B)."""
    have = set(ranks)
    if ACE in have and QUEEN in have and KING not in have:
        return True
    if KING in have and ACE not in have and QUEEN not in have:
        return True
    return False


def highest_trump(k, table, cards):
    trumps = trumps_in(k, table, cards)
    return max(trumps, key=rank) if trumps else None


def trump_lead(k, table, cards):
    """The highest trump when it is the highest out, else the lowest."""
    trumps = trumps_in(k, table, cards)
    if not trumps:
        return None
    top = max(trumps, key=rank)
    return top if table.sure(top) else min(trumps, key=rank)


def initial_trumps(k, table):
    mine = set(k.hand)
    for _, plays, _ in k.tricks:
        mine.update(c for s, c in plays if s == k.seat and c != FACE_DOWN)
    mine.update(c for s, c in k.trick if s == k.seat and c != FACE_DOWN)
    t = table.trump
    trumps = [c for c in mine if t is not None and t != NT and suit(c) == t]
    side_aces = [c for c in mine if not is_joker(c) and rank(c) == ACE and suit(c) != t]
    return trumps, side_aces


def melder_lead(k, table, p):
    cards = k.legal
    trumps, side_aces = initial_trumps(k, table)
    honours = sum(1 for c in trumps if rank(c) in (ACE, KING, QUEEN))
    good = len(trumps) >= p.good_trump_count and honours >= p.good_trump_honours
    ruff_plan = len(trumps) >= 5 and not side_aces
    opps_trump = opps_may_trump(k, table)
    led_trump = any(leader == k.seat and plays and plays[0][1] != FACE_DOWN and suit(plays[0][1]) == table.trump
                    for leader, plays, _ in k.tricks)

    def draw():
        if not opps_trump or (ruff_plan and led_trump):
            return None
        top = highest_trump(k, table, cards)
        return top if top is not None and table.sure(top) else None

    def makker_in():
        if table.ace_fallen or k.selvmakker or k.called is None:
            return None
        if k.fordaekt_waiting and k.fordaekt_card in cards:
            return k.fordaekt_card
        mine = [c for c in cards if suit(c) == k.called and not is_fordaekt(k, c)]
        return min(mine, key=rank) if mine else None

    steps = [(draw, "draw_trump"), (makker_in, "makker_in")]
    if not good:
        steps.reverse()
    steps += [(lambda: signal_lead(k, table, cards), "signal_suit"),
              (lambda: cash(k, table, cards, opps_trump), "cash"),
              (lambda: joker_lead(k, cards, opps_trump), "joker_lead"),
              (lambda: long_lead(k, table, cards, shortest=ruff_plan), "long_suit"),
              (lambda: highest_trump(k, table, cards), "trump_last")]
    for step, reason in steps:
        card = step()
        if card is not None:
            return card, reason
    return lowest_card(cards), "any"


def esmakker_lead(k, table, p):
    cards = k.legal
    opps_trump = opps_may_trump(k, table)
    if first_lead(k):
        card = trump_lead(k, table, cards)
        if card is not None:
            return card, "makker_trump"
    ace = C.ace(k.called)
    if ace in cards:
        return ace, "show_ace"
    if opps_trump:
        card = trump_lead(k, table, cards)
        if card is not None:
            return card, "makker_trump"
    card = signal_lead(k, table, cards)
    if card is not None:
        return card, "signal_suit"
    card = return_lead(k, table, cards, k.melder)
    if card is not None:
        return card, "return_suit"
    card = long_lead(k, table, cards)
    if card is not None:
        return card, "long_suit"
    card = highest_trump(k, table, cards)
    if card is not None:
        return card, "trump_last"
    return lowest_card(cards), "any"


def return_lead(k, table, cards, seat):
    """§6.6: the suit `seat` led last (not trump, not the called suit):
    the lowest from 4+, the highest from 2."""
    for s in reversed(table.led[seat]):
        if s == table.trump or (seat == k.melder and s == k.called):
            continue
        mine = [c for c in side_cards(k, table, cards) if suit(c) == s]
        if mine:
            return max(mine, key=rank) if len(mine) == 2 else min(mine, key=rank)
    return None


def defender_lead(k, table, p):
    cards = k.legal
    opps_trump = opps_may_trump(k, table)
    card = cash(k, table, cards, False if first_lead(k) else opps_trump)
    if card is not None:
        return card, "cash"
    card = joker_lead(k, cards, opps_trump)
    if card is not None:
        return card, "joker_lead"
    if not first_lead(k):
        trumps = trumps_in(k, table, cards)
        top = max(trumps, key=rank) if trumps else None
        if top is not None and table.sure(top) and sum(1 for c in table.unseen if suit(c) == table.trump) >= 2:
            return top, "top_trump"
    card = signal_lead(k, table, cards)
    if card is not None:
        return card, "signal_suit"
    mate = partner(k, table)
    if mate is not None:
        card = return_lead(k, table, cards, mate)
        if card is not None:
            return card, "return_suit"
    card = long_lead(k, table, cards, avoid_bad=True)
    if card is not None:
        return card, "long_suit"
    trumps = trumps_in(k, table, cards)
    if trumps:
        return min(trumps, key=rank), "trump_last"
    return lowest_card(cards), "any"


def lowest_card(cards):
    plain = [c for c in cards if not is_joker(c)]
    return min(plain, key=lambda c: (rank(c), c)) if plain else min(cards)


def follow(k, table, p):
    cards = k.legal
    trick = k.trick
    leader_card = trick[0][1]
    led = -1 if leader_card != FACE_DOWN and is_joker(leader_card) else table.suit_of(leader_card)
    winner = table.winner(trick)
    mate = partner(k, table)
    if k.esmakker == k.seat and k.called is not None and led == k.called and C.ace(k.called) in cards:
        return C.ace(k.called), "lay_ace"
    following = [c for c in cards if (not is_joker(c) and suit(c) == led and led >= 0) or (led == k.called and is_fordaekt(k, c))]
    if following:
        def rk(c):
            return -1 if is_fordaekt(k, c) else rank(c)

        low = min(following, key=lambda c: (rk(c), c))
        if mate is not None and winner == mate and (len(trick) == 3 or mate_sure(k, table, trick)):
            return low, "makker_wins"
        beating = sorted((c for c in following if table.winner(trick + [(k.seat, FACE_DOWN if is_fordaekt(k, c) else c)]) == k.seat),
                         key=lambda c: (rk(c), c))
        if len(trick) == 1:
            seq = [c for c in following if not is_fordaekt(k, c) and table.sure(c)]
            if len(seq) >= 2 and beating and min(seq, key=rank) in beating:
                return min(seq, key=rank), "follow_sequence"
            return low, "follow_low"
        if beating:
            first = beating[0]
            if k.seat == k.melder and len(trick) < 3 and not table.sure(first):
                sure = [c for c in beating if table.sure(c)]
                taken = k.tricks_won[k.seat] + (k.tricks_won[mate] if mate is not None else 0)
                winners = sum(1 for c in k.hand if table.sure(c))
                if sure and taken + winners < M.number(k.melding):
                    return sure[0], "no_finesse"
            return first, "follow_win"
        return low, "follow_low"
    if led < 0:
        if k.rules.joker_trumpable and (mate is None or trick[0][0] != mate):
            card = lowest_winning_trump(k, table, cards, trick)
            if card is not None:
                return card, "ruff"
        return afkast(k, table, cards, p)
    if winner != k.seat and (mate is None or winner != mate):
        card = lowest_winning_trump(k, table, cards, trick)
        if card is not None:
            return card, "ruff"
    return afkast(k, table, cards, p)


def mate_sure(k, table, trick):
    """The partner's card in the stik wins for sure: no card out beats it."""
    card = next(c for s, c in trick if s == table.winner(trick))
    if card == FACE_DOWN or is_joker(card):
        return card != FACE_DOWN
    s = suit(card)
    if rank(card) <= table.highest_out(s):
        return False
    t = table.trump
    if t is not None and t != NT and s != t and table.trumps_out():
        return False
    return True


def lowest_winning_trump(k, table, cards, trick):
    trumps = sorted(trumps_in(k, table, cards), key=rank)
    for c in trumps:
        if table.winner(trick + [(k.seat, c)]) == k.seat:
            return c
    return None


def afkast(k, table, cards, p):
    """§6.6: a discard that signals by the bord's rule "Afkast"."""
    side = side_cards(k, table, cards)
    if not side:
        plain = [c for c in cards if not is_joker(c) and not is_fordaekt(k, c)]
        if plain:
            return min(plain, key=lambda c: (rank(c), c)), "afkast"
        return min(cards), "afkast"
    suits = sorted({suit(c) for c in side})
    guarded = [s for s in suits if not king_guard(ranks_in(k.hand, s))]
    suits = guarded or suits
    t = table.trump
    if k.rules.afkast == "spil_den_her":
        wanted = [s for s in suits if len(cards_in(side, s)) >= 2 and
                  (ACE in ranks_in(side, s) or (KING in ranks_in(side, s) and QUEEN in ranks_in(side, s)))]
        if wanted:
            s = min(wanted, key=lambda s: (-quick_tricks(ranks_in(side, s)), s))
            return min(cards_in(side, s), key=rank), "afkast_spil"
    elif t is not None and t != NT and trumps_in(k, table, k.hand):
        empty = [s for s in suits if not any(table.sure(c) for c in cards_in(side, s))]
        if empty:
            s = min(empty, key=lambda s: (len(cards_in(side, s)), s))
            return min(cards_in(side, s), key=rank), "afkast_renonce"
    s = min(suits, key=lambda s: (quick_tricks(ranks_in(side, s)), len(cards_in(side, s)), s))
    return min(cards_in(side, s), key=rank), "afkast"


def king_guard(ranks):
    """A suit where a discard would bare or throw the king (§6.6)."""
    return KING in ranks and ACE not in ranks and len(ranks) <= 2


# -- sol ------------------------------------------------------------------------------

def sol_unseen_above(k, card):
    """Whether a card of the suit higher than `card` is still out."""
    seen = set(k.hand)
    for _, plays, _ in k.tricks:
        seen.update(c for _, c in plays)
    seen.update(c for _, c in k.trick)
    s = suit(card)
    return any(suit(c) == s and sol_value(c) > sol_value(card) for c in range(52) if c not in seen)


def sol_targets(k):
    return [s for s in k.players if s != k.seat and s not in k.vaeltet]


def sol_defending(k, p):
    if k.seat not in k.players or k.seat in k.vaeltet:
        return True
    plain = [c for c in k.hand if not is_joker(c)]
    all_safe = all(suit_level(sol_values(plain, s), p) == SAFE for s in range(4))
    return all_safe and bool(sol_targets(k))


def sol_play(k, p):
    if sol_defending(k, p):
        return sol_defend(k, p)
    cards = k.legal
    if not k.trick:
        return sol_lead(k, cards, p)
    lead_card = k.trick[0][1]
    if is_joker(lead_card):
        return sol_afkast(k, cards, p)
    led = suit(lead_card)
    following = [c for c in cards if not is_joker(c) and suit(c) == led]
    if not following:
        return sol_afkast(k, cards, p)
    top = max(sol_value(c) for _, c in k.trick if not is_joker(c) and suit(c) == led)
    under = [c for c in following if sol_value(c) < top]
    if under:
        return max(under, key=sol_value), "sol_under"
    return max(following, key=sol_value), "sol_high"


def sol_lead(k, cards, p):
    plain = [c for c in cards if not is_joker(c)]
    if not plain:
        return min(cards), "any"
    levels = {s: suit_level(sol_values(plain, s), p) for s in range(4) if cards_in(plain, s)}
    spare = k.most_stik - k.tricks_won[k.seat] > 0
    if spare:
        danger = [s for s in sorted(levels) if levels[s] == DANGER]
        for s in danger:
            high = max(cards_in(plain, s), key=sol_value)
            safe_left = [t for t in levels if t != s and levels[t] == SAFE]
            if sol_value(high) >= p.sol_take and not sol_unseen_above(k, high) and safe_left:
                return high, "sol_take"
    singles = [cards_in(plain, s)[0] for s in sorted(levels) if len(cards_in(plain, s)) == 1]
    singles = [c for c in singles if sol_value(c) <= p.sol_singleton_lead]
    if singles:
        return min(singles, key=lambda c: (sol_value(c), c)), "sol_lead"
    safe = [c for c in plain if levels[suit(c)] == SAFE]
    if safe:
        return min(safe, key=lambda c: (sol_value(c), c)), "sol_lead"
    return min(plain, key=lambda c: (sol_value(c), c)), "sol_lead"


def sol_afkast(k, cards, p):
    plain = [c for c in cards if not is_joker(c)]
    jokers = [c for c in cards if is_joker(c)]
    if not plain:
        return min(cards), "sol_afkast"
    levels = {s: suit_level(sol_values(plain, s), p) for s in range(4) if cards_in(plain, s)}
    if jokers and all(level == SAFE for level in levels.values()):
        return jokers[0], "sol_afkast"
    s = min(levels, key=lambda s: (levels[s], len(cards_in(plain, s)), -max(sol_value(c) for c in cards_in(plain, s)), s))
    return max(cards_in(plain, s), key=sol_value), "sol_afkast"


def sol_voids(k):
    void = [[False] * 4 for _ in range(4)]
    led_by = []
    clearly_safe = [[False] * 4 for _ in range(4)]
    for leader, plays, _ in [*k.tricks, (None, k.trick, None)]:
        if not plays or is_joker(plays[0][1]):
            continue
        led = suit(plays[0][1])
        led_by.append((plays[0][0], led))
        top = max(sol_value(c) for _, c in plays if not is_joker(c) and suit(c) == led)
        for seat, c in plays[1:]:
            if not is_joker(c) and suit(c) != led:
                void[seat][led] = True
            if not is_joker(c) and suit(c) == led and sol_value(c) <= 3 and top >= 10:
                clearly_safe[seat][led] = True
    return void, led_by, clearly_safe


def middle_card(cards, p):
    return min(cards, key=lambda c: (abs(sol_value(c) - p.sol_middle), sol_value(c), c))


def sol_defend(k, p):
    cards = k.legal
    plain = [c for c in cards if not is_joker(c)]
    targets = sol_targets(k)
    void, led_by, clearly_safe = sol_voids(k)
    if not plain:
        return min(cards), "any"
    if not k.trick:
        if k.open_hand is not None and k.melder in targets:
            best = None
            for s in sorted({suit(c) for c in plain}):
                values = sol_values(k.open_hand, s)
                if not values:
                    continue
                weak = max(v - (2 * i + 1) for i, v in enumerate(values))
                if best is None or weak > best[1]:
                    best = (s, weak)
            if best is not None:
                return min(cards_in(plain, best[0]), key=sol_value), "sol_defend_lead"
        suits = sorted({suit(c) for c in plain})
        if not k.tricks:
            s = min(suits, key=lambda s: (len(cards_in(plain, s)), s))
            mine = cards_in(plain, s)
            return (mine[0] if len(mine) == 1 else middle_card(mine, p)), "sol_defend_lead"
        options = [s for s in suits if not any(void[t][s] for t in targets)] or suits
        options = [s for s in options if not any(seat == t and s == led for seat, led in led_by for t in targets)] or options
        options = [s for s in options if not any(clearly_safe[t][s] for t in targets)] or options
        chosen = None
        for seat, led in led_by:
            if seat not in k.players and led in options:
                chosen = led
                break
        if chosen is None:
            chosen = min(options, key=lambda s: (len(cards_in(plain, s)), s))
        mine = cards_in(plain, chosen)
        return (middle_card(mine, p) if len(mine) >= 3 else min(mine, key=sol_value)), "sol_defend_lead"
    lead_seat, lead_card = k.trick[0]
    led = -1 if is_joker(lead_card) else suit(lead_card)
    following = [c for c in plain if suit(c) == led] if led >= 0 else []
    if not following:
        suits = sorted({suit(c) for c in plain})
        options = [s for s in suits if not any(void[t][s] for t in targets)] or suits
        s = min(options, key=lambda s: (len(cards_in(plain, s)), -max(sol_value(c) for c in cards_in(plain, s)), s))
        return max(cards_in(plain, s), key=sol_value), "sol_defend_afkast"
    in_suit = [(seat, c) for seat, c in k.trick if not is_joker(c) and suit(c) == led]
    top_seat, top_card = max(in_suit, key=lambda sc: sol_value(sc[1]))
    top = sol_value(top_card)
    if lead_seat in targets and sol_value(lead_card) <= p.sol_cover and top_seat == lead_seat:
        above = [c for c in following if sol_value(c) > top]
        if above:
            return min(above, key=sol_value), "sol_cover"
    if top_seat in targets:
        under = [c for c in following if sol_value(c) < top]
        if under:
            return max(under, key=sol_value), "sol_defend_under"
    return min(following, key=sol_value), "sol_defend_low"
