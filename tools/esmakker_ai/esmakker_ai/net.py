"""The net (DouZero-style): it scores each legal action given what the seat
may know (features.py), and from the state alone predicts the seat's
expected points for the runde, its own stik and its makker's, who holds
the called ace (relative seat 0-3, or the kitty), and its chance to win the
spil (a logit).

The Q and value heads work in points / points_scale. Q is the runde's
points plus the spil's part (agent.targets: what the runde did to the
seat's chance to win the spil, priced in points); value the runde's points
alone.
"""

import numpy as np
import torch
from torch import nn

from . import features as F

MAKKER_CLASSES = 5  # relative seat 0-3 holds the called ace, 4: the kitty


class EsmakkerNet(nn.Module):
    def __init__(self, hidden=512, action_hidden=128, points_scale=10.0, state_bits=F.STATE_BITS):
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
        self.register_buffer("points_scale", torch.tensor(float(points_scale)))

    def encode_state(self, states):
        return self.state(states)

    def q_values(self, h, actions):
        return self.q(torch.cat([h, self.action(actions)], dim=1)).squeeze(1)

    def heads(self, h):
        return {"value": self.value(h).squeeze(1), "stik": self.stik(h), "makker": self.makker(h),
                "win": self.win(h).squeeze(1)}

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
    with torch.inference_mode():
        s = unpack_bits(torch.from_numpy(packed).to(device))
        counts_t = torch.from_numpy(counts).to(device)
        h = model.encode_state(s).repeat_interleave(counts_t, dim=0)
        q = model.q_values(h, actions[torch.from_numpy(flat).to(device)])
        width = int(counts.max())
        starts = torch.cumsum(counts_t, 0) - counts_t
        cols = torch.arange(width, device=device)
        index = (starts[:, None] + cols).clamp_(max=q.shape[0] - 1)
        padded = q[index].masked_fill_(cols >= counts_t[:, None], float("-inf"))
        best = padded.argmax(dim=1)
        return q.cpu().numpy(), best.cpu().numpy()


def pick_device(name="auto"):
    if name != "auto":
        return torch.device(name)
    if torch.cuda.is_available():
        return torch.device("cuda")
    if getattr(torch.backends, "mps", None) and torch.backends.mps.is_available():
        return torch.device("mps")
    return torch.device("cpu")


def build(config):
    model = EsmakkerNet(config.hidden, config.action_hidden, config.points_scale)
    # a stik net (config no_sol) never melder sol: its players read this off
    # the model, so snapshots, evaluation and the rating play it the same way
    model.no_sol = bool(getattr(config, "no_sol", False))
    return model
