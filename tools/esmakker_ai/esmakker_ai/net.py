"""The net (DouZero-style): it scores each legal action given what the seat
may know (features.py), and from the state alone predicts the seat's
expected points for the runde, its own stik and its makker's, who holds
the called ace (relative seat 0-3, or the kitty), and its chance to win the
spil (a logit).

The Q and value heads work in points / points_scale. Q is the runde's
points plus the spil's part (agent.targets: what the runde did to the
seat's chance to win the spil, priced in points); value the runde's points
alone.

With config `contract` the net also has a contract head: for each trump
(clubs, diamonds, hearts, spades, trumflÃ¸s) a distribution over the stik
the melder's side (melder and esmakker) takes, 0-13, if this seat becomes
the melder with that trump. It learns only from runder where the seat did
become melder (Anders: "det er kun som melder det betyder noget"), so it
is what the seat may expect when it wins the melding and chooses trump.
With `contract_mix` the value of each stik melding priced from it (the
best trump, the point table: contract_bid_values) is blended into the Q of
the seat's bids everywhere the net scores a bid: greedy play, the search's
Gumbel draw, the inference server (mix_bids).
"""

import numpy as np
import torch
from torch import nn

from . import features as F
from . import meldinger as M
from . import scoring as S
from .rules import STANDARD

MAKKER_CLASSES = 5  # relative seat 0-3 holds the called ace, 4: the kitty
CONTRACT_TRUMPS = 5  # clubs, diamonds, hearts, spades, trumflÃ¸s (actions.TRUMP + t)
CONTRACT_STIK = 14   # the side's stik, 0-13
STIK_BIDS = M.SOL    # bid ids 0-23 are the stik meldinger (actions.BID + id)
_BIDDING_BIT = F.PHASE + F.PHASE_INDEX["bidding"]


class EsmakkerNet(nn.Module):
    def __init__(self, hidden=512, action_hidden=128, points_scale=10.0, state_bits=F.STATE_BITS, contract=False):
        super().__init__()
        self.state = nn.Sequential(
            nn.Linear(state_bits, hidden), nn.ReLU(),
            nn.Linear(hidden, hidden), nn.ReLU(),
            nn.Linear(hidden, hidden), nn.ReLU())
        self.action = nn.Sequential(nn.Linear(F.ACTION_BITS, action_hidden), nn.ReLU())
        self.q = nn.Sequential(nn.Linear(hidden + action_hidden, 256), nn.ReLU(), nn.Linear(256, 1))
        self.value = nn.Linear(hidden, 1)
        self.stik = nn.Linear(hidden, 2)          # own stik, makker's stik
        self.makker = nn.Linear(hidden, MAKKER_CLASSES)
        self.win = nn.Linear(hidden, 1)           # logit of the seat's share of the spil's win
        # logits of the side's stik per trump if this seat becomes melder (config contract)
        self.contract = nn.Linear(hidden, CONTRACT_TRUMPS * CONTRACT_STIK) if contract else None
        self.contract_mix = 0.0
        self.register_buffer("points_scale", torch.tensor(float(points_scale)))

    def encode_state(self, states):
        return self.state(states)

    def q_values(self, h, actions):
        return self.q(torch.cat([h, self.action(actions)], dim=1)).squeeze(1)

    def heads(self, h):
        out = {"value": self.value(h).squeeze(1), "stik": self.stik(h), "makker": self.makker(h),
               "win": self.win(h).squeeze(1)}
        if self.contract is not None:
            out["contract"] = self.contract_logits(h)
        return out

    def contract_logits(self, h):
        """[n, CONTRACT_TRUMPS, CONTRACT_STIK]: per trump, the logits of the
        side's stik if this seat becomes melder with it."""
        return self.contract(h).view(-1, CONTRACT_TRUMPS, CONTRACT_STIK)

    def forward(self, states, actions):
        h = self.encode_state(states)
        return self.q_values(h, actions), self.heads(h)


def unpack(packed):
    """uint8 rows of packed bits -> float32 numpy rows of 0/1."""
    return np.unpackbits(packed, axis=-1, bitorder="little").astype(np.float32)


def unpack_bits(packed):
    """uint8 [n, bytes] on any device -> float32 [n, bytes * 8], little-endian bits
    (unpack on the tensor's device)."""
    shifts = torch.arange(8, device=packed.device, dtype=torch.uint8)
    return ((packed.unsqueeze(-1) >> shifts) & 1).reshape(packed.shape[0], -1).float()


def score_requests(model, actions, device, states, cands):
    """Q of every candidate of many decisions in one forward pass:
    `states` the decisions' state bytes, `cands` their candidate action ids,
    `actions` the action table on the device. The bits are unpacked on the
    device, and each decision's best candidate (the first of the highest Q,
    as np.argmax) is found there too. Returns (q, best): q a numpy array of
    all the candidates' Q in order, best a numpy array of each decision's
    index into its candidates."""
    n = len(states)
    counts = np.fromiter((len(c) for c in cands), np.int64, n)
    flat = np.fromiter((a for c in cands for a in c), np.int64, int(counts.sum()))
    packed = np.frombuffer(bytearray(b"".join(states)), np.uint8).reshape(n, -1)  # writable, for torch
    return score_arrays(model, actions, device, packed, counts, flat)


MAX_SCORED = 1 << 17  # candidates per forward pass: the server's batch may hold millions (search rollouts)


def score_arrays(model, actions, device, packed, counts, flat):
    """score_requests on arrays: `packed` uint8 [n, STATE_BYTES] (writable),
    `counts` int64 [n] candidates per decision, `flat` int64 the candidate
    action ids in order (the inference server's batches, inference.py).
    A batch of more than MAX_SCORED candidates goes in parts, whole
    decisions each: with meldinger by simulation 40 game groups' rollouts
    asked for 2.5 million at once, 10 GB of the Q layer (27 Oct)."""
    if len(flat) > MAX_SCORED and len(counts) > 1:
        ends = np.cumsum(counts)
        cut = max(1, int(np.searchsorted(ends, MAX_SCORED, side="right")))
        q1, b1 = score_arrays(model, actions, device, packed[:cut], counts[:cut], flat[:ends[cut - 1]])
        q2, b2 = score_arrays(model, actions, device, packed[cut:], counts[cut:], flat[ends[cut - 1]:])
        return np.concatenate([q1, q2]), np.concatenate([b1, b2])
    with torch.inference_mode():
        s = unpack_bits(torch.from_numpy(packed).to(device))
        counts_t = torch.from_numpy(counts).to(device)
        flat_t = torch.from_numpy(flat).to(device)
        encoded = model.encode_state(s)
        # each candidate's state; output_size given, so no wait for the device
        rows = torch.repeat_interleave(torch.arange(len(counts), device=device), counts_t,
                                       output_size=len(flat))
        q = model.q_values(encoded[rows], actions[flat_t])
        q = mix_bids(model, s, encoded, q, rows, flat_t)
        width = int(counts.max())
        starts = torch.cumsum(counts_t, 0) - counts_t
        cols = torch.arange(width, device=device)
        index = (starts[:, None] + cols).clamp_(max=q.shape[0] - 1)
        padded = q[index].masked_fill_(cols >= counts_t[:, None], float("-inf"))
        best = padded.argmax(dim=1)
        return q.cpu().numpy(), best.cpu().numpy()


def melding_points(points=STANDARD.points):
    """float64 [STIK_BIDS, CONTRACT_TRUMPS, CONTRACT_STIK]: what the melder
    gets for each stik melding, trump and side stik (scoring.stik_points,
    melder and esmakker against two, no banks). A vip melding is scored by
    the kitty card that names its trump: the mean of the three. How a
    melding's trump is set is in contract_trumps."""
    table = np.zeros((STIK_BIDS, CONTRACT_TRUMPS, CONTRACT_STIK))
    side = (0, 2)
    for m in range(STIK_BIDS):
        for t in range(CONTRACT_TRUMPS):
            for k in range(CONTRACT_STIK):
                if M.pahaeng(m) == M.VIP:
                    value = sum(S.stik_points(m, side, k, t, points, card)[0] for card in (1, 2, 3)) / 3
                else:
                    value = S.stik_points(m, side, k, t, points)[0]
                table[m, t, k] = float(value)
    return table


def contract_trumps():
    """float [STIK_BIDS, CONTRACT_TRUMPS]: how each melding's trump is
    weighed. 1 for every trump the melder may choose (the best counts); a
    gode melding only in clubs; a vip melding's trump is turned up from the
    kitty, not chosen: its row holds the chance of each (the four suits
    alike, the joker trumflÃ¸s, 13:13:13:13:1) and the trumps are averaged."""
    out = np.ones((STIK_BIDS, CONTRACT_TRUMPS))
    for m in range(STIK_BIDS):
        if M.pahaeng(m) == M.GODE:
            out[m] = (1, 0, 0, 0, 0)
        elif M.pahaeng(m) == M.VIP:
            out[m] = np.array((13, 13, 13, 13, 1)) / 53
    return out


_CONTRACT_TABLES = {}


def _contract_tables(device):
    key = str(device)
    if key not in _CONTRACT_TABLES:
        with torch.inference_mode(False):  # first made while scoring, kept for training too
            _CONTRACT_TABLES[key] = _make_tables(device)
    return _CONTRACT_TABLES[key]


def _make_tables(device):
    return (torch.tensor(melding_points(), dtype=torch.float32, device=device),
            torch.tensor(contract_trumps(), dtype=torch.float32, device=device),
            torch.tensor([M.pahaeng(m) == M.VIP for m in range(STIK_BIDS)], device=device))


def contract_bid_values(logits):
    """What each stik melding is worth to a seat that becomes melder, in
    points: [n, STIK_BIDS] from contract logits [n, CONTRACT_TRUMPS,
    CONTRACT_STIK]. Per trump the melder's expected points over the side's
    stik, then the best trump the melding allows (for vip the mean over the
    trump it may turn up). Only the point table goes in; what the hand is
    worth is what the head learned."""
    table, trumps, vip = _contract_tables(logits.device)
    expected = torch.einsum("ntk,mtk->nmt", torch.softmax(logits.float(), dim=2), table)
    best = expected.masked_fill(trumps[None] == 0, float("-inf")).max(dim=2).values
    mean = (expected * trumps[None]).sum(dim=2)
    return torch.where(vip[None], mean, best)


def contract_expected_stik(logits):
    """[n, CONTRACT_TRUMPS]: the side's expected stik per trump."""
    k = torch.arange(CONTRACT_STIK, device=logits.device, dtype=torch.float32)
    return (torch.softmax(logits.float(), dim=2) * k).sum(dim=2)


def mix_bids(model, s, h, q, rows, flat):
    """Blends contract_bid_values into q (points / points_scale; returned)
    where the candidate is a stik melding and its state in the meldingsrunde:
    q <- (1 - mix) q + mix value. `s` the states' bits, `h` their encodings,
    `rows` each candidate's state index, `flat` its action id (tensors on one
    device). q unchanged without a contract head or with contract_mix 0."""
    mix = float(getattr(model, "contract_mix", 0.0) or 0.0)
    if not mix or getattr(model, "contract", None) is None:
        return q
    bid = (flat < STIK_BIDS) & (s[rows, _BIDDING_BIT] > 0)
    # every state's values at once (a few thousand multiply-adds each):
    # cheaper on the GPU than picking out the bidding states first, and no
    # wait for the device in between
    values = contract_bid_values(model.contract_logits(h)) / model.points_scale
    value = values[rows, flat.clamp(max=STIK_BIDS - 1)]
    return torch.where(bid, (1 - mix) * q + mix * value, q)


def score_one(model, s, cands):
    """(Q of one state's candidates with the contract blend, the state's
    encoding): `s` float [1, STATE_BITS] on the CPU, `cands` action ids
    (NetPlayer.scores, agent.explain)."""
    from .agent import ACTION_TABLE
    flat = torch.as_tensor(np.asarray(cands, np.int64))
    with torch.inference_mode():
        h = model.encode_state(s)
        q = model.q_values(h.expand(len(cands), -1), torch.from_numpy(ACTION_TABLE[cands]))
        return mix_bids(model, s, h, q, torch.zeros(len(cands), dtype=torch.long), flat), h


def pick_device(name="auto"):
    if name != "auto":
        return torch.device(name)
    if torch.cuda.is_available():
        return torch.device("cuda")
    if getattr(torch.backends, "mps", None) and torch.backends.mps.is_available():
        return torch.device("mps")
    return torch.device("cpu")


def build(config):
    model = EsmakkerNet(config.hidden, config.action_hidden, config.points_scale,
                        contract=bool(getattr(config, "contract", False)))
    # the contract blend in every bid the net scores (mix_bids), read off the model as no_sol
    model.contract_mix = float(getattr(config, "contract_mix", 0.0) or 0.0)
    if getattr(config, "bid_by_simulation", False) and model.contract is not None:
        # the net's own bids, inside the simulations and when it plays alone, are its contract
        # guess entirely (Anders: "det skal jo betyde hele meldingen 100%")
        model.contract_mix = 1.0
    # a stik net (config no_sol) never melder sol: its players read this off
    # the model, so snapshots, evaluation and the rating play it the same way
    model.no_sol = bool(getattr(config, "no_sol", False))
    return model
