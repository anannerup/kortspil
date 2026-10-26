"""The observation never shows a seat what it may not know (strategy doc
§3, "Botten kigger aldrig"): other hands, the kitty unless the seat saw it,
the fordækt card's face, and who holds the called ace.

Two kinds of proof, on runder played with random legal moves:

- Every card an observation names is one the seat has seen, worked out
  from the deal and the log alone (not from the observation code).
- Hidden-world swaps: deal the cards the seat cannot see differently
  (another seat holds the called ace, the kitty holds other cards) and
  replay the same actions; while they stay legal in the other world, the
  seat's observation must be exactly the same in both.
"""

import random
import unittest

from esmakker_ai import actions as A
from esmakker_ai import cards as C
from esmakker_ai import meldinger as M
from esmakker_ai.bots import RandomBot
from esmakker_ai.engine import IllegalAction, Round
from esmakker_ai.observation import FACE_DOWN, HIDDEN_DISCARD, HIDDEN_FORDAEKT, PLAY_FACE_DOWN, observe
from esmakker_ai.rules import Rules
from esmakker_ai.selfplay import play_runde, random_deal

RUNDER = 400


def played_runder(count, seed):
    rng = random.Random(seed)
    rules = Rules(esmakker_banks_first=False)
    for index in range(count):
        bots = [RandomBot(rng.randrange(1 << 30)) for _ in range(4)]
        yield play_runde(Round(random_deal(rng), index % 4, rules), bots)


def snapshots(r):
    """The runde rebuilt step by step: (round before the action, seat, action)."""
    step = Round(r.deal, r.dealer, r.rules)
    for seat, action in r.log:
        yield step, seat, action
        step.apply(seat, action)
    yield step, None, None


def cards_named(obs):
    """Every card an observation shows, wherever it is."""
    named = set(obs["hand"]) | set(obs["kitty_cards"]) | set(obs["kitty_seen"]) | set(obs["discarded"])
    named |= set(obs["turned"]) | set(obs["open_hand"] or ())
    named |= {card for _, card in obs["trick"]}
    named |= {card for _, plays, _ in obs["tricks"] for _, card in plays}
    if obs["fordaekt"]:
        named.add(obs["fordaekt"]["card"])
    for _, action in obs["log"]:
        if isinstance(action, tuple):
            named |= set(action)
        elif A.PLAY <= action < A.FORDAEKT:
            named.add(action - A.PLAY)
        elif A.FORDAEKT <= action < A.ACTION_COUNT:
            named.add(action - A.FORDAEKT)
    named.discard(FACE_DOWN)
    return named


class SeenTracker:
    """What each seat has seen, from the deal and the log alone."""

    def __init__(self, r):
        self.deal = r.deal
        self.seen = [set(r.deal[13 * s:13 * s + 13]) for s in range(4)]
        self.kitty = list(r.deal[52:])
        self.melder = None
        self.melding = None
        self.fordaekt = None
        self.turned = 0
        self.melder_hand = None

    def before(self, step):
        """Things a seat sees by the state of play rather than one action."""
        if step.melder is not None and self.melder is None:
            self.melder, self.melding = step.melder, step.melding
            self.melder_hand = set(self.seen[self.melder])
        if step.phase == "discarding":
            self.seen[step.declarer()] |= set(self.kitty)
        if step.phase == "exchanging":
            self.seen[step.to_act()] |= set(step.kitty)
        if (self.melding in M.OPEN_HAND) and step.tricks:
            for seat in range(4):
                self.seen[seat] |= set(C.cards_of(step.hands[self.melder]))

    def after(self, seat, action):
        if action == A.VEND:
            self.turned += 1
            for other in range(4):
                self.seen[other].add(self.kitty[self.turned - 1])
        elif isinstance(action, int) and A.FORDAEKT <= action < A.ACTION_COUNT:
            self.fordaekt = action - A.FORDAEKT
        elif isinstance(action, int) and A.PLAY <= action < A.FORDAEKT:
            card = action - A.PLAY
            for other in range(4):
                if card != self.fordaekt or seat != self.melder or other == self.melder:
                    self.seen[other].add(card)


def esmakker_may_be_known(step, seat):
    """REGLER/strategy: the esmakker is known to her, to the selvmakker once
    she saw the kitty, at halve to all, and to all once the ace falls or is
    turned, or the runde is over."""
    if step.kind != "stik" or step.called_ace is None:
        return False
    ace = C.ace(step.called_ace)
    played = any(card == ace for _, plays, _ in step.tricks for _, card, *_ in plays) or any(
        p[1] == ace and not p[4] for p in step.trick)
    if M.pahaeng(step.melding) == M.HALVE or played or step.complete() or ace in step.kitty[:step.turned]:
        return True
    if seat == step.melder:
        return step.kitty_taken and step.esmakker is None
    return seat == step.esmakker


class SeenCardsTest(unittest.TestCase):
    def test_an_observation_names_only_cards_the_seat_has_seen(self):
        checked = 0
        for r in played_runder(RUNDER, seed=11):
            tracker = SeenTracker(r)
            for step, seat, action in snapshots(r):
                tracker.before(step)
                for observer in range(4):
                    obs = observe(step, observer)
                    leaked = cards_named(obs) - tracker.seen[observer]
                    self.assertEqual(set(), leaked, f"seat {observer} at {step.tokens()!r}")
                    if obs["esmakker"] is not None or obs["selvmakker"]:
                        self.assertTrue(esmakker_may_be_known(step, observer), step.tokens())
                    checked += 1
                if seat is not None:
                    tracker.after(seat, action)
        self.assertGreater(checked, 50000)

    def test_hidden_actions_are_markers_for_the_others(self):
        found_fordaekt = found_discard = 0
        for r in played_runder(RUNDER, seed=12):
            if r.fordaekt is not None:
                for seat in range(4):
                    if seat == r.melder:
                        continue
                    obs = observe(r, seat)
                    actions = [action for _, action in obs["log"]]
                    self.assertIn(HIDDEN_FORDAEKT, actions)
                    self.assertIn(PLAY_FACE_DOWN, actions)
                    self.assertNotIn(A.PLAY + r.fordaekt, actions)
                    self.assertNotIn(r.fordaekt, cards_named(obs))
                    found_fordaekt += 1
            for seat in range(4):
                for actor, action in observe(r, seat)["log"]:
                    if actor != seat and isinstance(action, int) and action >= HIDDEN_DISCARD:
                        found_discard += 1
        self.assertGreater(found_fordaekt, 0)
        self.assertGreater(found_discard, 0)


def hidden_variant(r, observer, rng):
    """A deal the observer cannot tell from r's: the hands of the seats that
    are neither the observer nor the melder are dealt again among
    themselves; when the observer is not the melder and the melder takes the
    kitty before anyone sees it (no påhæng, gode), her hand and the kitty are
    dealt again too, so the called ace may move between them."""
    deal = list(r.deal)
    hands = [deal[13 * s:13 * s + 13] for s in range(4)]
    kitty = deal[52:]
    others = [s for s in range(4) if s not in (observer, r.melder)]
    pool = [card for s in others for card in hands[s]]
    rng.shuffle(pool)
    for index, s in enumerate(others):
        hands[s] = pool[13 * index:13 * index + 13]
    if observer != r.melder and r.kind == "stik" and M.pahaeng(r.melding) in (M.NONE, M.GODE):
        pool = hands[r.melder] + kitty
        rng.shuffle(pool)
        hands[r.melder], kitty = pool[:13], pool[13:]
    return [card for hand in hands for card in hand] + kitty


class HiddenWorldTest(unittest.TestCase):
    def test_a_seat_cannot_tell_hidden_worlds_apart(self):
        rng = random.Random(13)
        compared = esmakker_moved = kitty_moved = 0
        for r in played_runder(RUNDER, seed=13):
            if r.melder is None:
                continue
            for observer in range(4):
                variant = hidden_variant(r, observer, rng)
                one = Round(r.deal, r.dealer, r.rules)
                two = Round(variant, r.dealer, r.rules)
                for seat, action in r.log:
                    halve_revealed = r.kind == "stik" and M.pahaeng(r.melding) == M.HALVE and one.called_ace is not None
                    if halve_revealed:
                        break  # at halve the ace holder gives herself away to all
                    self.assertEqual(observe(one, observer), observe(two, observer),
                                     f"seat {observer} after {one.tokens()!r}")
                    compared += 1
                    if one.called_ace is not None and one.esmakker != two.esmakker:
                        esmakker_moved += 1
                    if one.kitty_taken and set(one.kitty) != set(two.kitty):
                        kitty_moved += 1
                    one.apply(seat, action)
                    try:
                        two.apply(seat, action)
                    except IllegalAction:
                        break  # the hidden cards now make a difference to what can be played
        self.assertGreater(compared, 20000)
        self.assertGreater(esmakker_moved, 500, "worlds where another seat holds the called ace")
        self.assertGreater(kitty_moved, 100, "worlds where the kitty held other cards")


if __name__ == "__main__":
    unittest.main()
