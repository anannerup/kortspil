"""The tensor engine (tengine.py) plays stik runder exactly as engine.Round:
thousands of random runder with random rules, from the first lead and from
random points in the play, played through both in lockstep with random
legal actions (fordækt at the melder's lead and out of turn included). At
every step the seat to act, the candidates, the hands, the stik and stik
won must be the same, and at the end the points."""

import random
import unittest

try:
    import torch
except ImportError:  # pragma: no cover
    torch = None

from esmakker_ai import actions as A
from esmakker_ai import cards as C
from esmakker_ai import features as F
from esmakker_ai import meldinger as M
from esmakker_ai.engine import BANKING, BIDDING, PLAYING, Round
from esmakker_ai.rules import Points, Rules
from esmakker_ai.selfplay import fordaekt_offer, random_deal


def device():
    return torch.device("cuda" if torch.cuda.is_available() else "cpu")


def random_rules(rng):
    order = ["vip", "halve", "gode"]
    rng.shuffle(order)
    halves = {k: rng.choice((1.5, 2, 3, 2.5)) for k in ("pahaeng", "trumflos", "klor", "vip_first", "bank")}
    stakes = {str(n): rng.choice((0.5, 1, 1.5, 2, 3)) for n in range(8, 14)}
    points = Points.from_dict({"stakes": stakes, **halves})
    return Rules(pahaeng_order=tuple(order), joker_trumpable=rng.random() < 0.5,
                 esmakker_banks_first=rng.random() < 0.5, points=points,
                 afkast=rng.choice(("renonce", "spil_den_her")))


def random_stik_round(rng, rules):
    """A random runde played (random legal actions) up to the first lead of
    a stik melding, banks and every påhæng included."""
    while True:
        r = Round(random_deal(rng), rng.randrange(4), rules)
        while r.phase != PLAYING and not r.over():
            if r.phase == BANKING:
                options = [(s, a) for s in range(4) for a in r.legal_actions(s)]
                seat, action = rng.choice(options)
                r.apply(seat, action)
                continue
            seat = r.to_act()
            size = r.discard_size(seat)
            if size:
                cards = rng.sample(C.cards_of(r.hand(seat)), rng.randint(0, size))
                r.apply(seat, tuple(cards))
                continue
            legal = r.legal_actions(seat)
            if r.phase == BIDDING:
                bids = [a for a in legal if a < A.PAS and not M.is_sol(a - A.BID)]
                if A.PAS in legal and (not bids or rng.random() < 0.55):
                    action = A.PAS
                elif bids:
                    action = rng.choice(bids[:6])
                else:
                    action = rng.choice([a for a in legal if a != A.JERNHAAND])
            else:
                action = rng.choice(legal)
            r.apply(seat, action)
        if r.phase == PLAYING and r.kind == "stik":
            return r


def candidates(r, offered):
    """(seat, offer, candidate actions) as agent.play_steps sees them."""
    if not offered and fordaekt_offer(r) is not None:
        return r.melder, True, [F.NO_FORDAEKT] + r.legal_actions(r.melder)
    seat = r.to_act()
    return seat, False, r.legal_actions(seat)


def random_choice(rng, cands):
    plain = [a for a in cands if not A.FORDAEKT <= a < A.ACTION_COUNT]
    return rng.choice(plain if plain and rng.random() < 0.5 else cands)


def apply_python(r, seat, action):
    if action != F.NO_FORDAEKT:
        r.apply(seat, action)


def random_states(rng, count, max_steps=48):
    """`count` stik runder in play at random points, with their `offered`."""
    rounds, offered = [], []
    for _ in range(count):
        r = random_stik_round(rng, random_rules(rng) if rng.random() < 0.8 else Rules())
        done = False
        for _ in range(rng.choice((0, 0, rng.randrange(max_steps)))):
            seat, offer, cands = candidates(r, done)
            done |= offer
            apply_python(r, seat, random_choice(rng, cands))
        rounds.append(r)
        offered.append(done)
    return rounds, offered


def hands_tensor(rounds):
    from esmakker_ai.tengine import _unpack_hands
    return _unpack_hands([r.hands for r in rounds], len(rounds))


@unittest.skipIf(torch is None, "PyTorch is not installed")
class TEngineParityTest(unittest.TestCase):
    def lockstep(self, seed, count):
        from esmakker_ai import tengine as T
        rng = random.Random(seed)
        dev = device()
        rounds, offered = random_states(rng, count)
        st = T.from_rounds(rounds, dev, offered)
        steps = 0
        while True:
            rows = (~st.done).nonzero().squeeze(1)
            if not rows.numel():
                break
            seat, mask, offer = T.decision(st, rows)
            seat_l, mask_c, offer_l = seat.tolist(), mask.cpu(), offer.tolist()
            slots = []
            for i, row in enumerate(rows.tolist()):
                r = rounds[row]
                s, o, cands = candidates(r, offered[row])
                self.assertEqual((s, o), (seat_l[i], offer_l[i]), f"seed {seed} row {row}")
                expected = sorted(T.ACTION_SLOT[a] for a in cands)
                self.assertEqual(expected, mask_c[i].nonzero().squeeze(1).tolist(), f"seed {seed} row {row}")
                action = random_choice(rng, cands)
                offered[row] |= o
                apply_python(r, s, action)
                slots.append(T.ACTION_SLOT[action])
            T.apply(st, rows, seat, torch.tensor(slots, device=dev), offer)
            steps += len(slots)
            sub = [rounds[i] for i in rows.tolist()]
            self.assertTrue(torch.equal(hands_tensor(sub), st.hands[rows].cpu()))
            self.assertEqual([r.tricks_won for r in sub], st.tricks_won[rows].tolist())
            self.assertEqual([r.trick_leader for r in sub], st.leader[rows].tolist())
            self.assertEqual([len(r.trick) for r in sub], st.trick_len[rows].tolist())
            self.assertEqual([r.complete() for r in sub], st.done[rows].tolist())
        self.assertTrue(all(r.complete() for r in rounds))
        expected = [[float(p) for p in r.points()] for r in rounds]
        self.assertEqual(expected, T.points(st).tolist())
        return steps

    def test_random_runder(self):
        steps = 0
        for seed in range(6):
            steps += self.lockstep(seed, 500)
        self.assertGreater(steps, 50_000)

    def test_coverage(self):
        """The random runder cover what the play rules turn on."""
        rng = random.Random(99)
        rounds, _ = random_states(rng, 400)
        self.assertTrue(any(r.esmakker is None for r in rounds))
        self.assertTrue(any(r.trump == 4 for r in rounds))
        self.assertTrue(any(r.banks for r in rounds))
        self.assertTrue(any(r.vip_card for r in rounds))
        self.assertTrue(any(r.fordaekt is not None for r in rounds))
        self.assertTrue(any(r.rules.joker_trumpable for r in rounds))
        pahaeng = {M.pahaeng(r.melding) for r in rounds}
        self.assertEqual({M.NONE, M.GODE, M.HALVE, M.VIP}, pahaeng)


if __name__ == "__main__":
    unittest.main()
