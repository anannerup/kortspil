"""The net's input (features.encode) for a TState (tengine.py), batched on
the tensors' device: encode(st, static, rows, seats) gives, bit for bit,
features.encode(r, seat, 0, spil) of each row's Round in the PLAYING phase,
unpacked (bool [n, F.STATE_BITS]; .float() for the net).

What stays the same while the stik are played (features._static_bits: the
meldingsrunde, the declaration, the kitty as the seat saw it, the rules,
the spil context) is made once per row and seat on the CPU by features
itself (static_rows); everything the card play changes is set here from the
TState. tests/test_tfeatures.py requires the same bits as features.encode
at every step of thousands of random runder.
"""

import numpy as np
import torch

from . import cards as C
from . import features as F
from .tbranch import static_packed



def static_rows(rounds, spils, device):
    """bool [B, 4, STATE_BITS]: each Round's static bits per seat (spils:
    a SpilContext or None per Round). Rounds of the same meldingsrunde,
    declaration and spil (clones of one world) are made once
    (tbranch.static_packed, then static_from_packed)."""
    return static_from_packed(*static_packed(rounds, spils), device)


def static_from_packed(packed, index, device):
    """static_rows from tbranch.static_packed's arrays (made where the
    Rounds are, e.g. a torch-free actor)."""
    # the bytes go to the device packed and are unpacked there (8x less to copy)
    raw = torch.from_numpy(np.require(packed, requirements=("C", "W"))).to(device)
    shifts = torch.arange(8, device=device, dtype=torch.uint8)
    unique = ((raw.unsqueeze(-1) >> shifts) & 1).reshape(*raw.shape[:-1], -1).bool()
    return unique[torch.from_numpy(index).to(device)]


_RANGES = {}


def _ranges(device):
    key = str(device)
    if key not in _RANGES:
        _RANGES[key] = (torch.arange(4, device=device), torch.arange(13, device=device),
                        torch.ones((), dtype=torch.bool, device=device))
    return _RANGES[key]


def encode(st, static, rows, seats):
    """bool [n, STATE_BITS]: features.encode(r, seat, 0, spil) for each row
    of `rows` seen from its seat in `seats` (no host sync)."""
    four, thirteen, true = _ranges(st.device)  # true on the device: CUDA graphs copy no host scalars
    n = rows.shape[0]
    at = torch.arange(n, device=st.device)
    x = static[rows, seats]  # advanced indexing copies
    x[:, F.HAND:F.HAND + C.DECK_SIZE] = st.hands[rows, seats]
    absk = (seats[:, None] + four) % 4  # relative seat k -> absolute
    rows4 = rows[:, None].expand(-1, 4)
    x[:, F.PLAYED[0]:F.PLAYED[0] + 4 * C.DECK_SIZE] = st.played[rows4, absk].reshape(n, -1)
    x[:, F.VOID:F.VOID + 16] = st.void[rows4, absk].reshape(n, -1)
    won = st.tricks_won[rows4, absk]
    x[:, F.TRICKS_WON:F.TRICKS_WON + 52] = (thirteen < won[:, :, None]).reshape(n, -1)
    x[at, F.TRICK_LEADER + (st.leader[rows] - seats) % 4] = true

    melder = st.melder[rows]
    is_melder = seats == melder
    esm = st.esmakker[rows]
    known = st.known[rows, seats] | st.ace_played[rows]
    esm_bit = torch.where(known, torch.where(esm < 0, torch.full_like(esm, 4), (esm - seats) % 4),
                          torch.full_like(esm, 5))
    x[at, F.ESMAKKER + esm_bit] = true

    fd = st.fordaekt[rows]
    laid = fd >= 0
    x[:, F.FORDAEKT_FLAGS] = laid
    x[:, F.FORDAEKT_FLAGS + 1] = laid & ~st.fd_played[rows]
    fd_col = fd.clamp(min=0)
    x[at, F.FORDAEKT_FACE + fd_col] |= is_melder & laid
    fd_done = st.fd_done[rows]
    x[at, F.PLAYED[0] + fd_col] |= is_melder & fd_done
    x[:, F.PLAYED_DOWN] |= ~is_melder & fd_done

    # the stik on the table
    trick_len = st.trick_len[rows]
    k = (st.leader[rows][:, None] + four - seats[:, None]) % 4  # [n, 4]: position p's seat, relative
    down = st.trick_down[rows] & ~is_melder[:, None]
    bit = torch.where(down, F.TRICK_DOWN + k, F.TRICK[0] + C.DECK_SIZE * k + st.trick_card[rows].clamp(min=0))
    valid = four < trick_len[:, None]
    at4 = at[:, None].expand(-1, 4)
    x[at4, bit] |= valid  # a row's four positions are four seats: distinct bits
    return x
