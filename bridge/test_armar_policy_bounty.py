# -*- coding: utf-8 -*-
"""Regression tests for the policy-bounty ABI bridge."""

import argparse
import json
import os
import sys
import unittest


HERE = os.path.dirname(os.path.abspath(__file__))
POLICY_ID = "0x" + "22" * 32
sys.path.insert(0, HERE)
import armar_policy_bounty as bridge  # noqa: E402
import policy_spec  # noqa: E402


def fixture(name):
    with open(os.path.join(HERE, "fixtures", name), encoding="utf-8") as handle:
        return json.load(handle)


class TestPolicyBountyBridge(unittest.TestCase):
    def setUp(self):
        self.spec = policy_spec.load(policy_spec.default_path())
        self.case = fixture("policy-bounty-jhjd.json")

    def test_inputs_match_the_solidity_tuple(self):
        raw = bridge.encode_policy_inputs(self.spec)
        self.assertEqual(len(raw), 96)
        self.assertEqual(
            raw[:32].hex(),
            "fbfe47b0bc48301022f5aa04390b175eef2701458913f8646a8f3b7b0a7cc7d0",
        )
        self.assertEqual(
            raw[32:64].hex(),
            "e6a7e49857602ac84257dc78f0960506f87cd7f3" + "00" * 12,
        )
        self.assertEqual(int.from_bytes(raw[64:96], "big"), 1500)

    def test_jhjd_evidence_matches_the_solidity_fixture(self):
        raw = bridge.encode_evidence(self.case)
        self.assertEqual(len(raw), 160)
        self.assertEqual(raw[0:7].hex(), "2e2d14270a1a10")
        self.assertEqual(raw[32:64], (503).to_bytes(32, "big"))
        self.assertEqual(raw[64:96], (190).to_bytes(32, "big"))
        self.assertEqual(raw[96:104].hex(), "030f000000000000")
        self.assertEqual(int.from_bytes(raw[128:160], "big"), 2)

    def test_control_evidence_matches_the_solidity_fixture(self):
        raw = bridge.encode_evidence(fixture("policy-bounty-control-4hah.json"))
        self.assertEqual(raw[0:7].hex(), "123a380e192a20")
        self.assertEqual(raw[96:104].hex(), "0506070000000000")
        self.assertEqual(int.from_bytes(raw[128:160], "big"), 3)

    def test_output_is_ready_for_current_core_interface(self):
        output = bridge.build(self.case, self.spec, POLICY_ID)
        self.assertEqual(output["inputsLength"], 96)
        self.assertEqual(output["evidenceLength"], 160)
        self.assertEqual(output["commit"]["threshold"], 0)
        self.assertEqual(output["commit"]["comparator"], "AtMost")
        self.assertEqual(output["commit"]["policyId"], POLICY_ID)
        self.assertEqual(output["commit"]["registeredPolicyExpected"]["maxEvidenceLen"], 160)
        self.assertTrue(output["verdict"]["violation"])

    def test_policy_id_invalido_se_rechaza(self):
        with self.assertRaises(argparse.ArgumentTypeError):
            bridge.policy_id_hex("0x1234")


if __name__ == "__main__":
    unittest.main()
