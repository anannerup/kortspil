"""One runde of es-makker (Esmakker::Round with Bidding, Play and SolPlay).

Unlike the Ruby Round, which is immutable and replays its log on every
action, this Round is mutable for speed: `apply` changes it in place and
`clone` copies it (for search). The rules are the Ruby engine's, kept equal
by the parity check (parity.py); comments name the Ruby method each part
mirrors. Cards are ints (cards.py), actions ints or discard tuples
(actions.py).
"""

from . import actions as A
from . import cards as C
from . import meldinger as M
from . import scoring as S
from .rules import STANDARD

BIDDING = "bidding"
REDEAL = "redeal"
CHOOSING_TRUMP = "choosing_trump"
CALLING_ACE = "calling_ace"
TURNING = "turning"
DISCARDING = "discarding"
BANKING = "banking"
EXCHANGING = "exchanging"
PLAYING = "playing"
COMPLETE = "complete"

STIK_COUNT = 13
MAX_BANKS = 2
NOTRUMP = A.NOTRUMP
ALL_TRUMPS = tuple(A.TRUMP + t for t in range(5))
HALVE_TRUMPS = ALL_TRUMPS[:4]


class IllegalAction(ValueError):
    pass


class Round:
    """A trick in progress is a list of plays (seat, card, suit, rank,
    fordaekt): suit -1 for a joker; the fordækt card has the called ace's
    suit and rank -1; at a sol-melding an ace has rank -1. A completed
    stik is (leader, plays, winner)."""

    __slots__ = (
        "rules", "ladder", "deal", "dealer", "forhand", "deal_hands", "jernhaand_seats", "hands", "kitty", "log",
        "phase",
        # bidding
        "melding", "holder", "challenger", "serveret", "bid_to_act", "passed", "went_with_log", "history", "outcome",
        # play (stik melding and sol-melding)
        "kind", "melder", "trump", "called_ace", "esmakker", "turned", "vip_card", "banks", "kitty_taken",
        "discarded", "tricks", "trick", "trick_leader", "tricks_won", "ace_played", "fordaekt", "fordaekt_played",
        "players", "exchange_order", "turn", "laid_away", "kitty_seen",
    )

    def __init__(self, deal, dealer=0, rules=STANDARD):
        deal = tuple(deal)
        if len(deal) != C.DECK_SIZE or len(set(deal)) != C.DECK_SIZE:
            raise ValueError("a deal is 55 different cards: four hands of 13, then the kitty")
        if dealer not in (0, 1, 2, 3):
            raise ValueError("the kortgiver is a seat 0-3")
        self.rules = rules
        self.ladder = M.ladder_for(rules.pahaeng_order)
        self.deal = deal
        self.dealer = dealer
        self.forhand = (dealer + 1) % 4
        self.deal_hands = tuple(C.mask(deal[13 * s:13 * s + 13]) for s in range(4))
        self.jernhaand_seats = tuple(s for s in range(4) if self.deal_hands[s] & ~C.NUMBER_MASK == 0)
        self.hands = list(self.deal_hands)
        self.kitty = list(deal[52:])
        self.log = []
        self.phase = BIDDING
        self.melding = None
        self.holder = None
        self.challenger = None
        self.serveret = None
        self.bid_to_act = self.forhand
        self.passed = []
        self.went_with_log = []
        self.history = []
        self.outcome = None
        self.kind = None
        self.melder = None
        self.trump = None
        self.called_ace = None
        self.esmakker = None
        self.turned = 0
        self.vip_card = None
        self.banks = []
        self.kitty_taken = False
        self.discarded = None
        self.tricks = []
        self.trick = []
        self.trick_leader = None
        self.tricks_won = [0, 0, 0, 0]
        self.ace_played = False
        self.fordaekt = None
        self.fordaekt_played = False
        self.players = ()
        self.exchange_order = ()
        self.turn = 0
        self.laid_away = [(), (), (), ()]
        self.kitty_seen = [(), (), (), ()]

    # -- building ------------------------------------------------------

    @classmethod
    def replay(cls, deal, dealer, log, rules=STANDARD, check=True):
        """A runde rebuilt from its log [(seat, action), ...]."""
        r = cls(deal, dealer, rules)
        for seat, action in log:
            r.apply(seat, action, check=check)
        return r

    def clone(self):
        other = Round.__new__(Round)
        for name in Round.__slots__:
            setattr(other, name, getattr(self, name))
        other.hands = self.hands[:]
        other.kitty = self.kitty[:]
        other.log = self.log[:]
        other.passed = self.passed[:]
        other.went_with_log = self.went_with_log[:]
        other.history = self.history[:]
        other.banks = self.banks[:]
        other.tricks = self.tricks[:]
        other.trick = self.trick[:]
        other.tricks_won = self.tricks_won[:]
        other.laid_away = self.laid_away[:]
        other.kitty_seen = self.kitty_seen[:]
        return other

    # -- state ---------------------------------------------------------

    def complete(self):
        return self.phase == COMPLETE

    def redeal(self):
        return self.phase == REDEAL

    def over(self):
        return self.phase == COMPLETE or self.phase == REDEAL

    def to_act(self):
        """The seat to act; None in the bank window and once over."""
        phase = self.phase
        if phase == PLAYING:
            return (self.trick_leader + len(self.trick)) % 4
        if phase == BIDDING:
            return self.bid_to_act
        if phase == CALLING_ACE:
            return self.melder
        if phase in (CHOOSING_TRUMP, TURNING, DISCARDING):
            return self.declarer()
        if phase == EXCHANGING:
            return self.exchange_order[self.turn]
        return None

    def declarer(self):
        """Who names trump and takes the kitty: the melder, at halve the
        esmakker (Play#declarer)."""
        if self.kind == "stik" and M.pahaeng(self.melding) == M.HALVE and self.esmakker is not None:
            return self.esmakker
        return self.melder

    def went_with(self):
        return [seat for seat, m in self.went_with_log if m == self.melding]

    def selvmakker(self):
        return self.called_ace is not None and self.esmakker is None

    def hand(self, seat):
        """The seat's cards now (a bitmask); the seat exchanging at a
        sol-melding also holds the kitty (SolPlay#hand)."""
        if self.phase == EXCHANGING and seat == self.to_act():
            return self.hands[seat] | C.mask(self.kitty)
        return self.hands[seat]

    def fordaekt_waiting(self):
        return self.fordaekt is not None and not self.fordaekt_played

    def turned_cards(self):
        return self.kitty[:self.turned] if self.kind == "stik" else []

    def vaeltet(self):
        most = M.MOST_STIK[self.melding]
        return [p for p in self.players if self.tricks_won[p] > most]

    def next_dealer(self):
        if self.phase == REDEAL:
            return self.outcome[2]
        return (self.dealer + 1) % 4

    def esmakker_known(self, seat):
        """Whether the seat knows who the esmakker is (Play#esmakker_known?)."""
        if self.kind != "stik" or self.called_ace is None:
            return False
        if (M.pahaeng(self.melding) == M.HALVE or self.ace_played or self.phase == COMPLETE
                or C.ace(self.called_ace) in self.turned_cards()):
            return True
        if seat == self.melder:
            return self.kitty_taken and self.esmakker is None
        return seat == self.esmakker

    def discard_size(self, seat):
        """How many cards the seat lays away now, 0 when it is not to."""
        if seat != self.to_act():
            return 0
        if self.phase == DISCARDING:
            return C.KITTY_SIZE
        if self.phase == EXCHANGING:
            return len(self.kitty)
        return 0

    # -- legal actions ---------------------------------------------------

    def legal_actions(self, seat):
        """Every action the seat may take now (a discard is not listed:
        see discard_size). In the bank window: bank where the bord accepts
        it, and the melder's "bankslut" (the window closing)."""
        phase = self.phase
        if phase == PLAYING:
            if seat != (self.trick_leader + len(self.trick)) % 4:
                return []
            moves = [A.PLAY + card for card in self.legal_cards(seat)]
            if seat == self.melder and self.kind == "stik" and self.fordaekt_allowed():
                moves.extend(A.FORDAEKT + card for card in C.cards_of(self.hands[seat]))
            return moves
        if phase == BIDDING:
            return self._bidding_legal(seat)
        if phase == BANKING:
            if not self.banks:
                if seat == self.melder:
                    return [A.BANKSLUT]
                if seat == self.esmakker and not self.rules.esmakker_banks_first:
                    return []
                return [A.BANK]
            return [A.BANK, A.BANKSLUT] if seat == self.melder else []
        if seat != self.to_act():
            return []
        if phase == CHOOSING_TRUMP:
            return list(HALVE_TRUMPS if M.pahaeng(self.melding) == M.HALVE else ALL_TRUMPS)
        if phase == CALLING_ACE:
            return [A.ACE + suit for suit in self.callable_aces()]
        if phase == TURNING:
            return [A.ACCEPTER, A.VEND] if self.turned else [A.VEND]
        return []

    def _bidding_legal(self, seat):
        out = []
        if self.melding is None and seat in self.jernhaand_seats:
            out.append(A.JERNHAAND)
        if seat != self.bid_to_act:
            return out
        if self.serveret is not None:
            out.append(A.SELV)
        else:
            out.extend(A.BID + m for m in self.ladder.above(self.melding))
        if self.melding is not None and self.melding >= M.SOL:
            out.append(A.MED)
        out.append(A.PAS)
        return out

    def callable_aces(self):
        own = self.deal_hands[self.melder]
        free = [suit for suit in range(4) if not own >> C.ace(suit) & 1]
        return free or [0, 1, 2, 3]

    def fordaekt_allowed(self):
        return (self.phase == PLAYING and not self.tricks and not self.trick and self.fordaekt is None
                and self.esmakker is not None and not self.hands[self.melder] & C.SUIT_MASK[self.called_ace])

    def legal_cards(self, seat):
        """The cards the seat may play into the stik (LegalMoves), the
        melder's waiting fordækt card included (by its real card)."""
        hand = self.hands[seat]
        fd = self.fordaekt if seat == self.melder and self.fordaekt is not None and not self.fordaekt_played else None
        led = self.trick[0][2] if self.trick else -1
        if led < 0:
            out = C.cards_of(hand)
            if fd is not None:
                out.append(fd)
            return out
        follow = hand & C.SUIT_MASK[led]
        fd_follows = fd is not None and self.called_ace == led
        if follow or fd_follows:
            out = C.cards_of(follow | (hand & C.JOKER_MASK))
            if fd_follows:
                out.append(fd)
            return out
        out = C.cards_of(hand)
        if fd is not None:
            out.append(fd)
        return out

    # -- applying --------------------------------------------------------

    def apply(self, seat, action, check=True):
        """Applies the seat's action in place. With check (the default) an
        illegal action raises IllegalAction; self-play may pass check=False
        for actions taken from legal_actions."""
        if check:
            self._check(seat, action)
        self.log.append((seat, action))
        if isinstance(action, tuple):
            if self.kind == "sol":
                self._exchange(seat, action)
            else:
                self._discard(action)
            return
        phase = self.phase
        if phase == PLAYING:
            if self.kind == "sol":
                self._sol_play(seat, action - A.PLAY)
            elif action >= A.FORDAEKT:
                card = action - A.FORDAEKT
                self.fordaekt = card
                self.hands[self.melder] &= ~(1 << card)
            else:
                self._play(seat, action - A.PLAY)
        elif phase == BIDDING:
            self._bid(seat, action)
        else:
            self._declare(seat, action)

    def _check(self, seat, action):
        if self.over():
            raise IllegalAction("the runde is over")
        if isinstance(action, tuple):
            size = self.discard_size(seat)
            hand = self.hand(seat)
            if (size == 0 or len(action) != size or len(set(action)) != size
                    or any(not (0 <= card < 55 and hand >> card & 1) for card in action)):
                raise IllegalAction(f"seat {seat} may not lay away {A.token(action)}")
            return
        if action not in self.legal_actions(seat):
            raise IllegalAction(f"seat {seat} may not {A.token(action)} in {self.phase}")

    # Bidding#replay
    def _bid(self, seat, action):
        if action == A.JERNHAAND:
            self.outcome = ("redeal", "jernhaand", self.dealer)
            self.phase = REDEAL
        elif action < A.PAS:
            opening = self.holder is None
            if not opening:
                self.serveret = self.holder
            self.melding = action
            self.holder = seat
            if opening:
                self._next_challenger(seat)
            else:
                self.bid_to_act = self.serveret
        elif action == A.SELV:
            self.holder = seat
            self.serveret = None
            self.bid_to_act = self.challenger
        elif action == A.PAS:
            self.passed.append(seat)
            if self.holder is None:
                if len(self.passed) == 4:
                    self.outcome = ("redeal", "all_passed", self.forhand)
                    self.phase = REDEAL
                else:
                    self.bid_to_act = self._next_active(seat)
            else:
                self.serveret = None
                self._next_challenger(self.challenger)
        elif action == A.MED:
            self.went_with_log.append((seat, self.melding))
            self.serveret = None
            self._next_challenger(self.challenger)
        self.history.append((seat, action))

    def _next_active(self, seat):
        went = [s for s, _ in self.went_with_log]
        for offset in (1, 2, 3):
            other = (seat + offset) % 4
            if other != self.holder and other not in self.passed and other not in went:
                return other
        return None

    def _next_challenger(self, seat):
        self.challenger = self._next_active(seat)
        self.bid_to_act = self.challenger
        if self.challenger is None:
            self.outcome = ("melder", self.holder, self.melding, tuple(self.went_with()))
            self._start_play()

    def _start_play(self):
        self.melder = self.holder
        self.trick_leader = self.melder
        if self.melding < M.SOL:
            self.kind = "stik"
            p = M.pahaeng(self.melding)
            if p == M.GODE:
                self.trump = C.CLUBS
            self.phase = CALLING_ACE if p != M.NONE else CHOOSING_TRUMP
        else:
            self.kind = "sol"
            self.players = (self.melder, *self.outcome[3])
            clockwise = [(self.melder + o) % 4 for o in (1, 2, 3)]
            self.exchange_order = (*self.players, *(s for s in clockwise if s not in self.players))
            self.trick_leader = self.forhand
            self.phase = EXCHANGING

    # Play#replay before the stik
    def _declare(self, seat, action):
        halve = M.pahaeng(self.melding) == M.HALVE
        if action < A.ACE:  # trump
            self.trump = action - A.TRUMP
            if halve:
                self._take_kitty()
            else:
                self.phase = CALLING_ACE
        elif action < A.VEND:  # call the ace
            suit = action - A.ACE
            self.called_ace = suit
            ace_bit = 1 << C.ace(suit)
            holder = next((s for s in range(4) if self.deal_hands[s] & ace_bit), None)  # None: in the kitty
            self.esmakker = None if holder == self.melder else holder
            if halve:
                self.phase = CHOOSING_TRUMP
            elif M.pahaeng(self.melding) == M.VIP:
                self.phase = TURNING
            else:
                self._take_kitty()
        elif action == A.VEND:
            self.turned += 1
            if self.turned == C.KITTY_SIZE:
                self._name_vip_trump()
        elif action == A.ACCEPTER:
            self._name_vip_trump()
        elif action == A.BANK:
            self.banks.append(seat)
            if len(self.banks) == MAX_BANKS:
                self.phase = PLAYING
        elif action == A.BANKSLUT:
            self.phase = PLAYING
        else:
            raise IllegalAction(f"unknown action {action!r}")

    def _name_vip_trump(self):
        card = self.kitty[self.turned - 1]
        self.vip_card = self.turned
        self.trump = NOTRUMP if card >= 52 else card // 13
        self._take_kitty()

    def _take_kitty(self):
        declarer = self.declarer()
        self.hands[declarer] |= C.mask(self.kitty)
        self.kitty_seen[declarer] = tuple(self.kitty)
        self.kitty_taken = True
        self.phase = DISCARDING

    def _discard(self, cards):
        self.discarded = cards
        self.hands[self.declarer()] &= ~C.mask(cards)
        self.phase = BANKING if M.pahaeng(self.melding) == M.VIP else PLAYING

    # Play#replay_play
    def _play(self, seat, card):
        if self.fordaekt is not None and not self.fordaekt_played and seat == self.melder and card == self.fordaekt:
            self.fordaekt_played = True
            self.trick.append((seat, card, self.called_ace, -1, True))
        else:
            self.hands[seat] &= ~(1 << card)
            if card >= 52:
                self.trick.append((seat, card, -1, 0, False))
            else:
                self.trick.append((seat, card, card // 13, card % 13, False))
                if self.called_ace is not None and card == C.ace(self.called_ace):
                    self.ace_played = True
        if len(self.trick) == 4:
            winner = self._stik_winner(self.trick)
            self.tricks.append((self.trick_leader, tuple(self.trick), winner))
            self.tricks_won[winner] += 1
            self.trick_leader = winner
            self.trick = []
            if len(self.tricks) == STIK_COUNT:
                self.phase = COMPLETE

    # Trick#winner
    def _stik_winner(self, plays):
        trump = self.trump
        trumps = [p for p in plays if p[2] == trump] if trump != NOTRUMP else []
        lead = plays[0]
        if lead[2] < 0 and (not trumps or not self.rules.joker_trumpable):
            return lead[0]
        pool = trumps or [p for p in plays if p[2] == lead[2]]
        return max(pool, key=lambda p: p[3])[0]

    # SolPlay#replay_exchange
    def _exchange(self, seat, cards):
        kitty = self.kitty
        chosen = set(cards)
        own = tuple(card for card in cards if card not in kitty)
        kept = [card for card in kitty if card not in chosen]
        self.kitty_seen[seat] = tuple(kitty)
        self.hands[seat] = (self.hands[seat] | C.mask(kept)) & ~C.mask(own)
        self.laid_away[seat] = own
        self.kitty = [card for card in kitty if card in chosen]
        self.turn += 1
        if not self.kitty or self.turn == 4:
            self.phase = PLAYING

    # SolPlay#replay_play
    def _sol_play(self, seat, card):
        self.hands[seat] &= ~(1 << card)
        if card >= 52:
            self.trick.append((seat, card, -1, 0, False))
        else:
            rank = card % 13
            self.trick.append((seat, card, card // 13, -1 if rank == C.ACE_RANK else rank, False))
        if len(self.trick) == 4:
            plays = self.trick
            if plays[0][2] < 0:
                winner = plays[0][0]
            else:
                led = plays[0][2]
                winner = max((p for p in plays if p[2] == led), key=lambda p: p[3])[0]
            self.tricks.append((self.trick_leader, tuple(plays), winner))
            self.tricks_won[winner] += 1
            self.trick_leader = winner
            self.trick = []
            if len(self.tricks) == STIK_COUNT or len(self.vaeltet()) == len(self.players):
                self.phase = COMPLETE

    # -- result ----------------------------------------------------------

    def side(self):
        return [s for s in (self.melder, self.esmakker) if s is not None]

    def points(self):
        """Runde points per seat (Fractions); [] until complete."""
        if self.phase != COMPLETE:
            return []
        if self.kind == "sol":
            value = self.rules.points.sol_amount(M.SOL_KINDS[self.melding - M.SOL])
            return S.sol_points(self.players, self.vaeltet(), value)
        side = self.side()
        return S.stik_points(self.melding, side, sum(self.tricks_won[s] for s in side), self.trump,
                             self.rules.points, self.vip_card, len(self.banks))

    def result(self):
        """How the runde ended, shaped like Ruby's RundeResult#to_h /
        SolResult#to_h (codes as strings, points as Fractions); None until
        complete."""
        if self.phase != COMPLETE:
            return None
        if self.kind == "sol":
            vaeltet = self.vaeltet()
            return {"kind": "sol", "melder": self.melder, "melding": M.CODES[self.melding], "trump": None,
                    "called_ace": None, "esmakker": None, "selvmakker": False, "tricks_won": list(self.tricks_won),
                    "stik": self.tricks_won[self.melder], "gik_hjem": self.melder not in vaeltet, "vip_card": None,
                    "banks": 0, "points": self.points(),
                    "sol": {"players": list(self.players), "most_stik": M.MOST_STIK[self.melding], "vaeltet": vaeltet}}
        stik = sum(self.tricks_won[s] for s in self.side())
        return {"kind": "played", "melder": self.melder, "melding": M.CODES[self.melding],
                "trump": A.trump_code(self.trump), "called_ace": C.SUITS[self.called_ace],
                "esmakker": self.esmakker, "selvmakker": self.selvmakker(), "tricks_won": list(self.tricks_won),
                "stik": stik, "gik_hjem": stik >= M.number(self.melding), "vip_card": self.vip_card,
                "banks": len(self.banks), "points": self.points()}

    def tokens(self):
        return A.log_string(self.log)
