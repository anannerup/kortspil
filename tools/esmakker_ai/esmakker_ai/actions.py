"""Actions as ints, and the Ruby action-log tokens (Esmakker::Round.token).

Every action but a discard is one int in a flat space of ACTION_COUNT:

    0-27     bid the melding with that id (meldinger.py)
    28-31    pas, "det kan jeg selv", gå med, claim a jernhånd
    32-36    name trump C, D, H, S, trumfløs
    37-40    call the ace of C, D, H, S
    41-44    vip: turn the kitty's next card, take it as trump; bank;
             the bank window closes ("bankslut", the bord's timer)
    45-99    play card c (PLAY + c; the fordækt card by its real card)
    100-154  lay card c fordækt (FORDAEKT + c)

A discard (lay cards away, Discard) is a tuple of card ints.
"""

from . import cards as C
from . import meldinger as M

BID = 0
PAS, SELV, MED, JERNHAAND = 28, 29, 30, 31
TRUMP = 32  # + suit 0-3, + 4 trumfløs
ACE = 37  # + suit
VEND, ACCEPTER, BANK, BANKSLUT = 41, 42, 43, 44
PLAY = 45
FORDAEKT = 100
ACTION_COUNT = 155

NOTRUMP = 4
SIMPLE_TOKENS = {PAS: "pas", SELV: "selv", MED: "med", JERNHAAND: "jernhaand",
                 VEND: "vend", ACCEPTER: "accepter", BANK: "bank", BANKSLUT: "bankslut"}
TOKEN_ACTIONS = {token: action for action, token in SIMPLE_TOKENS.items()}


def trump_code(trump):
    return "trumfloes" if trump == NOTRUMP else C.SUITS[trump]


def is_discard(action):
    return isinstance(action, tuple)


def token(action):
    if isinstance(action, tuple):
        return "kast-" + "-".join(C.code(card) for card in action)
    if action < PAS:
        return M.CODES[action]
    if action in SIMPLE_TOKENS:
        return SIMPLE_TOKENS[action]
    if TRUMP <= action < ACE:
        return "trumf" + trump_code(action - TRUMP)
    if ACE <= action < VEND:
        return "es" + C.SUITS[action - ACE]
    if PLAY <= action < FORDAEKT:
        return C.code(action - PLAY)
    if FORDAEKT <= action < ACTION_COUNT:
        return "fordaekt-" + C.code(action - FORDAEKT)
    raise ValueError(f"not an action: {action!r}")


def parse(text):
    if text in TOKEN_ACTIONS:
        return TOKEN_ACTIONS[text]
    if len(text) == 2 and (text[0] == "X" or text[1] in C.SUITS):
        return PLAY + C.parse(text)
    if text.startswith("trumf"):
        rest = text[5:]
        return TRUMP + (NOTRUMP if rest == "trumfloes" else C.SUITS.index(rest))
    if text.startswith("es") and len(text) == 3:
        return ACE + C.SUITS.index(text[2])
    if text.startswith("kast-"):
        return tuple(C.parse(part) for part in text[5:].split("-"))
    if text.startswith("fordaekt-"):
        return FORDAEKT + C.parse(text[9:])
    return BID + M.parse(text)


def log_string(log):
    """The Ruby action log: "seat:token" entries, space-separated."""
    return " ".join(f"{seat}:{token(action)}" for seat, action in log)


def parse_log(text):
    out = []
    for entry in text.split():
        seat, tok = entry.split(":")
        out.append((int(seat), parse(tok)))
    return out
