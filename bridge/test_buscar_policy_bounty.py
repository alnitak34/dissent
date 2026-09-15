# -*- coding: utf-8 -*-
"""Tests for the candidate scanner."""

import os
import sys
import unittest


HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import buscar_policy_bounty as search  # noqa: E402


class TestPolicyBountySearch(unittest.TestCase):
    def test_finds_the_counterexample_without_a_named_winner(self):
        candidates = [
            os.path.join(HERE, "fixtures", "policy-bounty-control-4hah.json"),
            os.path.join(HERE, "fixtures", "policy-bounty-jhjd.json"),
        ]
        report = search.scan(list(reversed(candidates)))
        self.assertEqual(report["examined"], 2)
        self.assertEqual(report["valid"], 2)
        self.assertEqual(len(report["counterexamples"]), 1)
        self.assertEqual(report["counterexamples"][0]["case"], "historical-counterexample")

    def test_non_policy_json_is_rejected_not_counted_as_a_result(self):
        report = search.scan([os.path.join(HERE, "fixtures", "alnitak-river-minimal.json")])
        self.assertEqual(report["examined"], 1)
        self.assertEqual(report["valid"], 0)
        self.assertEqual(len(report["rejected"]), 1)
        self.assertEqual(report["counterexamples"], [])


if __name__ == "__main__":
    unittest.main()
