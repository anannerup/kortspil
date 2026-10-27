"""The card play of stik runder as batched torch tensors (on the GPU), for
search rollouts that play thousands of branches at once.

engine.Round is the reference: a TState is many Rounds in the PLAYING
phase of a stik melding, one row each, and the functions here are Round's
play rules vectorized over the rows: the decision to take (legal_cards and
the melder's fordækt, and the fordækt offer out of turn of
selfplay.fordaekt_offer), applying it (Round._play), the stik winner
(Round._stik_winner) and the points (Round.points). tests/test_tengine.py
plays thousands of random runder through both and requires the same at every
step.

A decision is a choice among SLOTS slots, the candidate actions of
features.candidates: slot 0 is "no fordækt" (F.NO_FORDAEKT, at the offer),
slot 1 + c plays card c (A.PLAY + c; the fordækt card by its real card),
slot 56 + c lays card c fordækt (A.FORDAEKT + c). SLOT_ACTION maps a slot
to its action id.

Sol, the meldingsrunde and the declaration stay on the CPU (engine.Round).
"""

from dataclasses import dataclass, fields

import torch

from . import actions as A
from . import cards as C
from . import features as F
from . import scoring as S
from .engine import PLAYING, STIK_COUNT

SLOTS = 1 + 2 * C.DECK_SIZE  # 111
NO_FD_SLOT = 0
PLAY_SLOT = 1
FD_SLOT = 1 + C.DECK_SIZE
SLOT_ACTION = (F.NO_FORDAEKT, *(A.PLAY + c for c in range(C.DECK_SIZE)), *(A.FORDAEKT + c for c in range(C.DECK_SIZE)))
ACTION_SLOT = {a: s for s, a in enumerate(SLOT_ACTION)}


@dataclass
class TState:
    """B stik runder in play, one per row. Seats are absolute (0-3); -1
    means none. Cards in a stik: trick_card/suit/rank/down per position
    0-3 from the leader (suit -1 a joker; the fordækt card has the called
    ace's suit and rank -1 and is face down)."""

    hands: torch.Tensor        # bool [B, 4, 55]
    played: torch.Tensor       # bool [B, 4, 55]: face-up cards each seat played in finished stik
    void: torch.Tensor         # bool [B, 4, 4]: seat showed out of suit (features' VOID)
    tricks_won: torch.Tensor   # long [B, 4]
    trick_card: torch.Tensor   # long [B, 4]
    trick_suit: torch.Tensor   # long [B, 4]
    trick_rank: torch.Tensor   # long [B, 4]
    trick_down: torch.Tensor   # bool [B, 4]
    trick_len: torch.Tensor    # long [B]
    n_tricks: torch.Tensor     # long [B]: finished stik
    leader: torch.Tensor       # long [B]
    trump: torch.Tensor        # long [B]: 0-3, 4 trumfløs
    called: torch.Tensor       # long [B]: the called ace's suit
    melder: torch.Tensor       # long [B]
    esmakker: torch.Tensor     # long [B], -1: selvmakker
    fordaekt: torch.Tensor     # long [B]: the fordækt card, -1 none
    fd_played: torch.Tensor    # bool [B]
    fd_done: torch.Tensor      # bool [B]: the fordækt card fell in a finished stik
    ace_played: torch.Tensor   # bool [B]
    called_led: torch.Tensor   # bool [B]: a finished stik was led in the called suit (ace_owed)
    fd_ok: torch.Tensor        # bool [B]: not a melder who knows she is selvmakker (fordaekt_allowed)
    known: torch.Tensor        # bool [B, 4]: esmakker_known per seat, but for the ace falling later
    joker_trumpable: torch.Tensor  # bool [B]
    offered: torch.Tensor      # bool [B]: the melder was asked about fordækt out of turn
    points_table: torch.Tensor  # float64 [B, 14, 4]: points per seat by the side's stik
    done: torch.Tensor         # bool [B]

    @property
    def size(self):
        return self.hands.shape[0]

    @property
    def device(self):
        return self.hands.device

    def clone(self):
        return TState(**{f.name: getattr(self, f.name).clone() for f in fields(self)})

    def select(self, rows):
        return TState(**{f.name: getattr(self, f.name)[rows] for f in fields(self)})


class _Tables:
    """Constant card tables on a device."""

    def __init__(self, device):
        cards = torch.arange(C.DECK_SIZE, device=device)
        self.suit = torch.where(cards < 52, cards // 13, torch.full_like(cards, -1))
        self.rank = torch.where(cards < 52, cards % 13, torch.zeros_like(cards))
        # suit_mask[s] for s 0-3; row 4 (a joker led: no suit) is empty
        self.suit_mask = torch.zeros(5, C.DECK_SIZE, dtype=torch.bool, device=device)
        for s in range(4):
            self.suit_mask[s, 13 * s:13 * s + 13] = True
        self.eye = torch.eye(C.DECK_SIZE, dtype=torch.bool, device=device)
        # tie order of the slots: as the CPU candidates' order (first max
        # wins): no fordækt, the cards played lowest first (the waiting
        # fordækt card after them: tie_rank), the fordækt cards
        order = torch.arange(SLOTS, device=device)
        order[FD_SLOT:] += 1
        self.slot_order = order


_TABLES = {}


def tables(device):
    key = str(device)
    t = _TABLES.get(key)
    if t is None:
        t = _TABLES[key] = _Tables(device)
    return t


# -- from Rounds ------------------------------------------------------------------

_POINTS_CACHE = {}


def _points_table(r):
    side = tuple(r.side())
    points = r.rules.points
    key = (r.melding, side, r.trump, id(points), r.vip_card, len(r.banks))
    entry = _POINTS_CACHE.get(key)
    if entry is None or entry[0] is not points:
        if len(_POINTS_CACHE) > 10_000:
            _POINTS_CACHE.clear()
        table = [[float(p) for p in S.stik_points(r.melding, side, k, r.trump, points, r.vip_card, len(r.banks))]
                 for k in range(STIK_COUNT + 1)]
        entry = _POINTS_CACHE[key] = (points, table)
    return entry[1]


def from_rounds(rounds, device, offered=None):
    """A TState of Rounds in the PLAYING phase of a stik melding (not
    changed). `offered`: per Round, whether the melder was asked about
    fordækt out of turn already (agent.play_steps' `offered`); default
    False."""
    n = len(rounds)
    hand_bits, played_bits, voids, tricks, downs, ints, flags, won, known, table = ([] for _ in range(10))
    history = {}  # the finished stik, shared by clones: worked out once
    for i, r in enumerate(rounds):
        if r.phase != PLAYING or r.kind != "stik":
            raise ValueError("from_rounds takes stik runder in the PLAYING phase")
        hand_bits.append(r.hands)
        key = (tuple(map(id, r.tricks)), r.called_ace)
        past = history.get(key)
        if past is None:
            past = history[key] = _history(r.tricks, r.called_ace)
        face_up, void, fd_done, called_led = past
        played_bits.append(face_up)
        void = list(void)
        card_row, suit_row, rank_row, down_row = [-1] * 4, [-1] * 4, [-1] * 4, [False] * 4
        if r.trick:
            led = r.trick[0][2]
            for p, (s, card, suit, rank, down) in enumerate(r.trick):
                card_row[p], suit_row[p], rank_row[p], down_row[p] = card, suit, rank, down
                if led >= 0 and suit >= 0 and suit != led:
                    void[4 * s + led] = True
        voids.append(void)
        tricks.append((card_row, suit_row, rank_row))
        downs.append(down_row)
        ints.append((len(r.trick), len(r.tricks), r.trick_leader, r.trump, r.called_ace, r.melder,
                     -1 if r.esmakker is None else r.esmakker, -1 if r.fordaekt is None else r.fordaekt))
        seat_known = [r.esmakker_known(s) for s in range(4)]
        fd_ok = not (r.esmakker is None and seat_known[r.melder])
        flags.append((r.fordaekt_played, fd_done, r.ace_played, called_led, fd_ok, r.rules.joker_trumpable,
                      bool(offered[i]) if offered is not None else False))
        won.append(r.tricks_won)
        known.append(seat_known)
        table.append(_points_table(r))
    ints = torch.tensor(ints, dtype=torch.long).reshape(n, 8)
    flags = torch.tensor(flags, dtype=torch.bool).reshape(n, 7)
    trick = torch.tensor(tricks, dtype=torch.long).reshape(n, 3, 4)
    st = TState(
        hands=_unpack_hands(hand_bits, n), played=_unpack_hands(played_bits, n),
        void=torch.tensor(voids, dtype=torch.bool).reshape(n, 4, 4),
        tricks_won=torch.tensor(won, dtype=torch.long).reshape(n, 4),
        trick_card=trick[:, 0], trick_suit=trick[:, 1], trick_rank=trick[:, 2],
        trick_down=torch.tensor(downs, dtype=torch.bool).reshape(n, 4),
        trick_len=ints[:, 0], n_tricks=ints[:, 1], leader=ints[:, 2], trump=ints[:, 3], called=ints[:, 4],
        melder=ints[:, 5], esmakker=ints[:, 6], fordaekt=ints[:, 7],
        fd_played=flags[:, 0], fd_done=flags[:, 1], ace_played=flags[:, 2], called_led=flags[:, 3],
        fd_ok=flags[:, 4], joker_trumpable=flags[:, 5], offered=flags[:, 6],
        known=torch.tensor(known, dtype=torch.bool).reshape(n, 4),
        points_table=torch.tensor(table, dtype=torch.float64).reshape(n, STIK_COUNT + 1, 4),
        done=ints[:, 1] >= STIK_COUNT)
    return TState(**{f.name: getattr(st, f.name).contiguous().to(device) for f in fields(st)})


def _history(finished, called):
    """(face-up cards per seat, void per seat * 4 + suit, the fordækt card
    fell, a stik was led in the called suit) of the finished stik."""
    face_up = [0, 0, 0, 0]
    void = [False] * 16
    fd_done = called_led = False
    for _, plays, _ in finished:
        led = plays[0][2]
        called_led |= led == called
        for s, card, suit, _, down in plays:
            if down:
                fd_done = True
            else:
                face_up[s] |= 1 << card
            if led >= 0 and suit >= 0 and suit != led:
                void[4 * s + led] = True
    return face_up, tuple(void), fd_done, called_led


def _unpack_hands(bits, n):
    """[[4 bitmasks] per row] -> bool [n, 4, 55]."""
    import numpy as np
    arr = np.array(bits, dtype="<u8").reshape(n, 4).view(np.uint8).reshape(n, 4, 8)
    unpacked = np.unpackbits(arr, axis=-1, bitorder="little")[:, :, :C.DECK_SIZE]
    return torch.from_numpy(unpacked.astype(bool))


# -- the rules, vectorized ----------------------------------------------------------


def to_act(st, rows):
    return (st.leader[rows] + st.trick_len[rows]) % 4


def fordaekt_allowed(st, rows):
    """Round.fordaekt_allowed per row."""
    t = tables(st.device)
    melder_hand = st.hands[rows, st.melder[rows]]
    void_called = ~(melder_hand & t.suit_mask[st.called[rows]]).any(1)
    return (st.n_tricks[rows] == 0) & (st.trick_len[rows] == 0) & (st.fordaekt[rows] < 0) & st.fd_ok[rows] & void_called


def decision(st, rows):
    """The decision each row takes now: (seat, candidate slot mask [n, SLOTS],
    offer). offer: the melder is offered fordækt out of turn (selfplay.
    fordaekt_offer, once, before the forhånd leads: candidates "no fordækt"
    and her cards fordækt); else the seat to act chooses among its legal
    actions (Round.legal_actions: legal_cards, and the melder's fordækt at
    her own lead)."""
    t = tables(st.device)
    n = rows.shape[0]
    seat = to_act(st, rows)
    melder = st.melder[rows]
    allowed = fordaekt_allowed(st, rows)
    offer = ~st.offered[rows] & (seat != melder) & allowed
    seat = torch.where(offer, melder, seat)
    hand = st.hands[rows, seat]
    called = st.called[rows]
    fordaekt = st.fordaekt[rows]
    trick_len = st.trick_len[rows]

    fd_avail = (seat == melder) & (fordaekt >= 0) & ~st.fd_played[rows]
    fd_bit = t.eye[fordaekt.clamp(min=0)] & fd_avail[:, None]
    led = torch.where(trick_len > 0, st.trick_suit[rows, 0], torch.full_like(trick_len, -1))
    ace = called * 13 + C.ACE_RANK
    ace_bit = t.eye[ace]
    owed = (seat == st.esmakker[rows]) & hand.gather(1, ace[:, None]).squeeze(1) & ~st.called_led[rows]
    any_card = hand | fd_bit
    follow = hand & t.suit_mask[torch.where(led < 0, torch.full_like(led, 4), led)]
    fd_follows = fd_avail & (called == led)
    follows = follow | (fd_bit & fd_follows[:, None])
    can_follow = follow.any(1) | fd_follows
    plays = torch.where(can_follow[:, None] & (led >= 0)[:, None], follows, any_card)
    owed_lead = hand & ~(t.suit_mask[called] & ~ace_bit)
    plays = torch.where((owed & (trick_len == 0))[:, None], owed_lead, plays)
    plays = torch.where((owed & (led == called))[:, None], ace_bit, plays)

    mask = torch.zeros(n, SLOTS, dtype=torch.bool, device=st.device)
    mask[:, PLAY_SLOT:FD_SLOT] = plays & ~offer[:, None]
    fd_lay = allowed & (seat == melder)
    mask[:, FD_SLOT:] = hand & fd_lay[:, None]
    mask[:, NO_FD_SLOT] = offer
    return seat, mask, offer


def tie_order(st, rows):
    """[n, SLOTS] the order of the slots among the CPU candidates (lower
    first): ties go to the first, as np.argmax. The waiting fordækt card is
    played after the hand's cards (legal_cards appends it)."""
    t = tables(st.device)
    n = rows.shape[0]
    order = t.slot_order.expand(n, SLOTS).clone()
    fordaekt = st.fordaekt[rows]
    waiting = (fordaekt >= 0) & ~st.fd_played[rows]
    at = torch.arange(n, device=st.device)
    col = PLAY_SLOT + fordaekt.clamp(min=0)
    order[at, col] = torch.where(waiting, torch.full_like(col, FD_SLOT), order[at, col])
    return order


def apply(st, rows, seat, slot, offer):
    """Applies each row's chosen slot (in place): the decision of
    decision(st, rows), its seat and offer flag. Rows must be distinct.
    Slot 0 ("no fordækt") changes nothing but `offered`, so a finished row
    given slot 0 stays as it is. No host sync: every row is written, the
    rows the slot does not change with their old values."""
    t = tables(st.device)
    st.offered[rows] |= offer
    melder = st.melder[rows]
    # lay fordækt
    lay = slot >= FD_SLOT
    lay_card = (slot - FD_SLOT).clamp(min=0)
    st.fordaekt[rows] = torch.where(lay, lay_card, st.fordaekt[rows])
    st.hands[rows, melder, lay_card] &= ~lay
    # play a card
    play = (slot >= PLAY_SLOT) & (slot < FD_SLOT)
    card = (slot - PLAY_SLOT).clamp(0, C.DECK_SIZE - 1)
    called = st.called[rows]
    fd_play = play & (seat == melder) & (st.fordaekt[rows] == card) & ~st.fd_played[rows]
    st.fd_played[rows] |= fd_play
    up = play & ~fd_play
    st.hands[rows, seat, card] &= ~up
    st.ace_played[rows] |= up & (card == called * 13 + C.ACE_RANK)
    suit = torch.where(fd_play, called, t.suit[card])
    rank = torch.where(fd_play, torch.full_like(card, -1), t.rank[card])
    pos = st.trick_len[rows]
    led = torch.where(pos > 0, st.trick_suit[rows, 0], suit)
    shows = play & (pos > 0) & (led >= 0) & (suit >= 0) & (suit != led)
    st.void[rows, seat, led.clamp(min=0)] |= shows
    at = pos.clamp(max=3)
    st.trick_card[rows, at] = torch.where(play, card, st.trick_card[rows, at])
    st.trick_suit[rows, at] = torch.where(play, suit, st.trick_suit[rows, at])
    st.trick_rank[rows, at] = torch.where(play, rank, st.trick_rank[rows, at])
    st.trick_down[rows, at] = torch.where(play, fd_play, st.trick_down[rows, at])
    st.trick_len[rows] = pos + play.long()
    _finish_trick(st, rows, play & (pos == 3))


def stik_winner(st, rows):
    """Round._stik_winner per row of a full stik: the winning seat."""
    suit = st.trick_suit[rows]
    rank = st.trick_rank[rows]
    trump = st.trump[rows]
    is_trump = (suit == trump[:, None]) & (trump != 4)[:, None]
    any_trump = is_trump.any(1)
    lead = suit[:, 0]
    pool = torch.where(any_trump[:, None], is_trump, suit == lead[:, None])
    pos = torch.where(pool, rank, torch.full_like(rank, -100)).argmax(1)  # ranks differ within the pool
    leader_wins = (lead < 0) & (~any_trump | ~st.joker_trumpable[rows])
    pos = torch.where(leader_wins, torch.zeros_like(pos), pos)
    return (st.leader[rows] + pos) % 4


def _finish_trick(st, rows, full):
    """The rows' stik that are `full` (bool per row) are won and cleared."""
    winner = stik_winner(st, rows)
    seats = (st.leader[rows][:, None] + torch.arange(4, device=st.device)) % 4
    down = st.trick_down[rows]
    shown = ~down & full[:, None]
    rows4 = rows[:, None].expand(-1, 4)
    cards = st.trick_card[rows].clamp(min=0)
    st.played[rows4, seats, cards] |= shown
    st.fd_done[rows] |= full & down.any(1)
    st.called_led[rows] |= full & (st.trick_suit[rows, 0] == st.called[rows])
    st.tricks_won[rows, winner] += full.long()
    st.leader[rows] = torch.where(full, winner, st.leader[rows])
    st.trick_len[rows] = torch.where(full, torch.zeros_like(winner), st.trick_len[rows])
    keep = ~full[:, None]
    for name in ("trick_card", "trick_suit", "trick_rank"):
        tensor = getattr(st, name)
        tensor[rows] = torch.where(keep, tensor[rows], torch.full_like(tensor[rows], -1))
    st.trick_down[rows] &= keep
    st.n_tricks[rows] += full.long()
    st.done[rows] = st.n_tricks[rows] >= STIK_COUNT


def side_stik(st):
    """The melder's and esmakker's stik together, per row."""
    rows = torch.arange(st.size, device=st.device)
    melder = st.tricks_won[rows, st.melder]
    esm = st.esmakker
    makker = torch.where(esm >= 0, st.tricks_won[rows, esm.clamp(min=0)], torch.zeros_like(melder))
    return melder + makker


def points(st):
    """Round.points() per row (float64 [B, 4]); meaningful once done."""
    rows = torch.arange(st.size, device=st.device)
    return st.points_table[rows, side_stik(st).clamp(max=STIK_COUNT)]
