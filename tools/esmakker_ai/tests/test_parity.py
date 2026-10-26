"""The recorded Ruby spil (tests/fixtures/parity_sample.jsonl.gz, written by
parity_record.rb) replay here step by step with nothing different."""

import unittest
from pathlib import Path

from esmakker_ai import meldinger as M
from esmakker_ai import parity

FIXTURE = Path(__file__).parent / "fixtures" / "parity_sample.jsonl.gz"


class ParityTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.report = parity.run(FIXTURE, verbose=False)

    def test_every_recorded_step_agrees_with_ruby(self):
        self.assertGreater(self.report["spil"], 100)
        self.assertGreater(self.report["steps"], 10000)
        self.assertEqual(0, self.report["failures"], "run `python -m esmakker_ai.parity` on the fixture for details")

    def test_the_sample_covers_every_melding_and_every_part_of_a_runde(self):
        coverage = self.report["coverage"]
        wanted = [f"melding:{code}" for code in M.CODES] + [
            "redeal:all_passed", "redeal:jernhaand", "det_kan_jeg_selv", "gaa_med", "selvmakker",
            "fordaekt", "banks:0", "banks:1", "banks:2", "vip_card:1", "vip_card:2", "vip_card:3",
            "trump:C", "trump:D", "trump:H", "trump:S", "trump:trumfloes",
            "sol_players:1", "sol_players:2", "sol_players:3", "sol_vaeltet:0", "sol_vaeltet:3",
            "fordaekt:out_of_turn", "first_lead:forhand_not_melder",
            "exchanged:0", "exchanged:1", "exchanged:2", "exchanged:3",
        ]
        missing = [key for key in wanted if not coverage[key]]
        self.assertEqual([], missing)


if __name__ == "__main__":
    unittest.main()
