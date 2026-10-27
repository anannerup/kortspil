"""Rollout branches as numpy arrays, without torch: what tengine.from_rounds
and tfeatures.static_rows read off engine.Rounds, so a torch-free actor
(actor_inference "server", inference.py) can export the branches it wants
played out and the process holding the net can load them
(tengine.from_arrays, tfeatures.static_from_packed) and play them on the
GPU (trollout).

branch_arrays(rounds, offered) gives the card play's state (TState's
fields, as numpy arrays); static_packed(rounds, spils) the bits of
features.encode that stay the same while the stik are played, per Round
and seat, made once per meldingsrunde, declaration and spil.
"""

import numpy as np

from . import features as F
from . import scoring as S
from .engine import PLAYING, STIK_COUNT

_FD_STATIC = 1 << F.FORDAEKT_FLAGS | ((1 << 55) - 1) << F.FORDAEKT_FACE  # tfeatures.encode sets these per step
_PLAYING_BIT = 1 << (F.PHASE + F.PHASE_INDEX["playing"])

_POINTS_CACHE = {}


def points_table(r):
    """The runde's points per seat by the side's stik, 0-13 (Round.points)."""
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


def history(finished, called):
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


def branch_arrays(rounds, offered=None):
    """{name: numpy array} of Rounds in the PLAYING phase of a stik melding
    (not changed): hands and played (uint64 [n, 4] card masks), void (bool
    [n, 16]), trick (int64 [n, 3, 4]: card, suit, rank by position), down
    (bool [n, 4]), ints (int64 [n, 8]: trick length, finished stik, leader,
    trump, called, melder, esmakker, fordækt card), flags (bool [n, 7]),
    won (int64 [n, 4]), known (bool [n, 4]), points_table (float64
    [n, 14, 4]). `offered`: per Round, whether the melder was asked about
    fordækt out of turn already (agent.play_steps' `offered`); default
    False. tengine.from_arrays makes the TState."""
    n = len(rounds)
    hand_bits, played_bits, voids, tricks, downs, ints, flags, won, known, table = ([] for _ in range(10))
    past_of = {}  # the finished stik, shared by clones: worked out once
    for i, r in enumerate(rounds):
        if r.phase != PLAYING or r.kind != "stik":
            raise ValueError("from_rounds takes stik runder in the PLAYING phase")
        hand_bits.append(r.hands)
        key = (tuple(map(id, r.tricks)), r.called_ace)
        past = past_of.get(key)
        if past is None:
            past = past_of[key] = history(r.tricks, r.called_ace)
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
        table.append(points_table(r))
    return {"hands": np.array(hand_bits, dtype="<u8").reshape(n, 4),
            "played": np.array(played_bits, dtype="<u8").reshape(n, 4),
            "void": np.array(voids, dtype=bool).reshape(n, 16),
            "trick": np.array(tricks, dtype=np.int64).reshape(n, 3, 4),
            "down": np.array(downs, dtype=bool).reshape(n, 4),
            "ints": np.array(ints, dtype=np.int64).reshape(n, 8),
            "flags": np.array(flags, dtype=bool).reshape(n, 7),
            "won": np.array(won, dtype=np.int64).reshape(n, 4),
            "known": np.array(known, dtype=bool).reshape(n, 4),
            "points_table": np.array(table, dtype=np.float64).reshape(n, STIK_COUNT + 1, 4)}


def static_key(r, spil):
    return (id(r.deal), id(r.rules), tuple(r.history), r.trump, r.called_ace, r.vip_card, r.turned,
            tuple(r.banks), r.discarded, r.exchanged, spil)


def static_packed(rounds, spils):
    """(packed uint8 [u, 4, STATE_BYTES], index int64 [n]): the static bits
    of features.encode per seat of each distinct meldingsrunde, declaration
    and spil (clones of one world are made once), and each Round's row
    among them (spils: a SpilContext or None per Round). The fordækt bits
    are left to tfeatures.encode; the phase is PLAYING."""
    made = {}
    index = []
    rows = []
    for r, spil in zip(rounds, spils):
        key = static_key(r, spil)
        i = made.get(key)
        if i is None:
            i = made[key] = len(rows)
            rows.append([(F._static_bits(r, seat, spil) & ~_FD_STATIC | _PLAYING_BIT).to_bytes(F.STATE_BYTES, "little")
                         for seat in range(4)])
        index.append(i)
    packed = np.frombuffer(b"".join(b for row in rows for b in row), np.uint8).reshape(len(rows), 4, F.STATE_BYTES)
    return packed, np.array(index, dtype=np.int64)
