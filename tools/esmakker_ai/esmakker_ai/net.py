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


def pick_device(name="auto"):
    if name != "auto":
        return torch.device(name)
    if torch.cuda.is_available():
        return torch.device("cuda")
    if getattr(torch.backends, "mps", None) and torch.backends.mps.is_available():
        return torch.device("mps")
    return torch.device("cpu")


def build(config):
    return EsmakkerNet(config.hidden, config.action_hidden, config.points_scale)
