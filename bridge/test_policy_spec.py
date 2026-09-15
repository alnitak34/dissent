# -*- coding: utf-8 -*-
"""Pruebas de identidad canónica de la política candidata."""

import copy
import json
import os
import sys
import unittest


HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import policy_spec as ps  # noqa: E402
import policy_bounty as pb  # noqa: E402


class TestPolicySpec(unittest.TestCase):
    def setUp(self):
        self.document = ps.load(ps.default_path())

    def test_key_order_does_not_change_identity(self):
        reversed_document = dict(reversed(list(self.document.items())))
        self.assertEqual(ps.policy_hash(self.document), ps.policy_hash(reversed_document))

    def test_frozen_policy_hash(self):
        self.assertEqual(
            ps.policy_hash(self.document).hex(),
            "fbfe47b0bc48301022f5aa04390b175eef2701458913f8646a8f3b7b0a7cc7d0",
        )

    def test_verifier_constants_match_frozen_policy(self):
        mixes = {
            tuple(name.split("/")): tuple(values)
            for name, values in self.document["pressure"]["mixBp"].items()
        }
        self.assertEqual(mixes, pb.KNOWN_PRESSURES)
        self.assertEqual(self.document["mandate"]["marginBp"], 1500)

    def test_margin_change_changes_identity(self):
        changed = copy.deepcopy(self.document)
        changed["mandate"]["marginBp"] = 1499
        self.assertNotEqual(ps.policy_hash(self.document), ps.policy_hash(changed))

    def test_mix_change_changes_identity(self):
        changed = copy.deepcopy(self.document)
        changed["pressure"]["mixBp"]["raise/any"][0] -= 1
        self.assertNotEqual(ps.policy_hash(self.document), ps.policy_hash(changed))

    def test_serialization_is_compact_utf8_json(self):
        encoded = ps.canonical_bytes(self.document)
        self.assertNotIn(b"\n", encoded)
        self.assertEqual(json.loads(encoded.decode("utf-8")), self.document)


if __name__ == "__main__":
    unittest.main()
