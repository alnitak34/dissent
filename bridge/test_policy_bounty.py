# -*- coding: utf-8 -*-
"""Tests del verificador independiente de River Safety Gate v1."""

import copy
import json
import os
import sys
import unittest


HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import policy_bounty as pb  # noqa: E402


def fixture(name):
    path = os.path.join(HERE, "fixtures", name)
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


class TestPokerRules(unittest.TestCase):
    def test_categories_come_from_poker_rules(self):
        c = pb.card
        self.assertEqual(pb.eval5(list(map(c, ["As", "Ks", "Qs", "Js", "Ts"])))[0], 8)
        self.assertEqual(pb.eval5(list(map(c, ["As", "Ad", "Ac", "Ah", "2s"])))[0], 7)
        self.assertEqual(pb.eval5(list(map(c, ["As", "Ad", "Ac", "2h", "2s"])))[0], 6)
        self.assertEqual(pb.eval5(list(map(c, ["As", "Js", "8s", "4s", "2s"])))[0], 5)
        self.assertEqual(pb.eval5(list(map(c, ["As", "2d", "3h", "4c", "5s"])))[0], 4)

    def test_best_five_of_seven(self):
        cards = list(map(pb.card, ["As", "Ad", "Ac", "2h", "2s", "Kd", "Qc"]))
        self.assertEqual(pb.eval7(cards), (6, 14, 2))


class TestHistoricalCases(unittest.TestCase):
    def test_jhjd_is_a_counterexample(self):
        result = pb.verify_case(fixture("policy-bounty-jhjd.json"))
        self.assertEqual(result["pressure"], ("raise", "any"))
        self.assertEqual(
            result["conditionedEquity"].numerator * 10**18
            // result["conditionedEquity"].denominator,
            320045667447306791,
        )
        self.assertTrue(result["oldAuthorizes"])
        self.assertFalse(result["conditionedAuthorizes"])
        self.assertTrue(result["violation"])
        self.assertEqual(result["opponentHands"], 990)

    def test_4hah_is_a_control(self):
        result = pb.verify_case(fixture("policy-bounty-control-4hah.json"))
        self.assertEqual(result["pressure"], ("multi", "small"))
        self.assertEqual(
            result["conditionedEquity"].numerator * 10**18
            // result["conditionedEquity"].denominator,
            772440501043841336,
        )
        self.assertTrue(result["oldAuthorizes"])
        self.assertTrue(result["conditionedAuthorizes"])
        self.assertFalse(result["violation"])

    def test_result_does_not_enter_the_verdict(self):
        data = fixture("policy-bounty-jhjd.json")
        original = pb.verify_case(data)["violation"]
        changed = copy.deepcopy(data)
        changed["historical"]["chipDelta"] = 999999
        self.assertEqual(pb.verify_case(changed)["violation"], original)

    def test_price_change_can_remove_the_violation(self):
        data = fixture("policy-bounty-jhjd.json")
        data["state"]["call"] = 100
        result = pb.verify_case(data)
        self.assertTrue(result["oldAuthorizes"])
        self.assertTrue(result["conditionedAuthorizes"])
        self.assertFalse(result["violation"])

    def test_empty_trace_is_rejected(self):
        data = fixture("policy-bounty-jhjd.json")
        data["state"]["actionTrace"] = []
        with self.assertRaisesRegex(ValueError, "non-empty"):
            pb.verify_case(data)

    def test_trace_must_end_with_opponent_river_aggression(self):
        data = fixture("policy-bounty-jhjd.json")
        data["state"]["actionTrace"] = [
            {"street": "River", "actor": "opponent", "action": "bet"},
            {"street": "River", "actor": "agent", "action": "raise"},
        ]
        with self.assertRaisesRegex(ValueError, "opponent aggression on River"):
            pb.verify_case(data)

    def test_trace_streets_must_be_ordered(self):
        data = fixture("policy-bounty-control-4hah.json")
        data["state"]["actionTrace"][1]["street"] = "Preflop"
        with self.assertRaisesRegex(ValueError, "ordered"):
            pb.verify_case(data)

    def test_raise_requires_a_prior_bet(self):
        data = fixture("policy-bounty-jhjd.json")
        data["state"]["actionTrace"] = [
            {"street": "River", "actor": "opponent", "action": "raise"}
        ]
        with self.assertRaisesRegex(ValueError, "requires prior aggression"):
            pb.verify_case(data)

    def test_two_bets_on_one_street_are_impossible(self):
        data = fixture("policy-bounty-jhjd.json")
        data["state"]["actionTrace"] = [
            {"street": "River", "actor": "agent", "action": "bet"},
            {"street": "River", "actor": "opponent", "action": "bet"},
        ]
        with self.assertRaisesRegex(ValueError, "must be a raise"):
            pb.verify_case(data)

    def test_same_actor_cannot_bet_then_raise(self):
        data = fixture("policy-bounty-jhjd.json")
        data["state"]["actionTrace"] = [
            {"street": "River", "actor": "opponent", "action": "bet"},
            {"street": "River", "actor": "opponent", "action": "raise"},
        ]
        with self.assertRaisesRegex(ValueError, "other actor"):
            pb.verify_case(data)

    def test_all_in_must_be_the_final_event(self):
        data = fixture("policy-bounty-jhjd.json")
        data["state"]["actionTrace"] = [
            {"street": "Turn", "actor": "opponent", "action": "all-in"},
            {"street": "River", "actor": "opponent", "action": "bet"},
        ]
        with self.assertRaisesRegex(ValueError, "all-in must be final"):
            pb.verify_case(data)

    def test_single_small_bet_is_outside_high_pressure_domain(self):
        data = fixture("policy-bounty-control-4hah.json")
        data["state"]["actionTrace"] = [
            {"street": "River", "actor": "opponent", "action": "bet"}
        ]
        with self.assertRaisesRegex(ValueError, "high-pressure domain"):
            pb.verify_case(data)

    def test_duplicate_cards_are_rejected(self):
        data = fixture("policy-bounty-jhjd.json")
        data["state"]["board"][0] = data["state"]["hole"][0]
        with self.assertRaisesRegex(ValueError, "distinct"):
            pb.verify_case(data)

    def test_margin_is_part_of_v1(self):
        data = fixture("policy-bounty-jhjd.json")
        data["policy"]["marginBp"] = 1
        with self.assertRaisesRegex(ValueError, "1500"):
            pb.verify_case(data)

    def test_old_range_below_six_uses_historical_relaxed_range_first(self):
        data = fixture("policy-bounty-jhjd.json")
        data["state"]["hole"] = ["2c", "3d"]
        data["state"]["board"] = ["Ah", "Kc", "Qh", "Jh", "Ts"]
        data["state"]["potFacingDecision"] = 70
        data["state"]["call"] = 30
        result = pb.verify_case(data)
        self.assertEqual(result["oldRangeHands"], 45)
        self.assertEqual(result["oldEquity"], 0)
        self.assertFalse(result["oldAuthorizes"])
        self.assertFalse(result["violation"])


if __name__ == "__main__":
    unittest.main()
