# -*- coding: utf-8 -*-
"""Pruebas del exportador de replays crudos."""

import os
import sys
import unittest


HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import exportar_policy_bounty as exporter  # noqa: E402
import policy_bounty as policy  # noqa: E402


HERO = "hero-id"
VILLAIN = "villain-id"


def action(sequence, street, agent_id, name, seat, move, pot, call=0, snapshot=None):
    return {
        "sequence": sequence,
        "type": "ActionTaken",
        "street": street,
        "agentId": agent_id,
        "payload": {
            "agentName": name,
            "seatNumber": seat,
            "action": move,
            "pot": pot,
            "callAmount": call,
            "reasoning": "pf3:potoddsini eq57 p27" if agent_id == HERO else "",
        },
        "snapshot": snapshot or {},
    }


def raw_replay(extra_active=False):
    seats = [
        {
            "agentId": HERO,
            "agentName": "Alnitak",
            "seatNumber": 3,
            "status": "Active",
            "holeCards": ["Jh", "Jd"],
        },
        {
            "agentId": VILLAIN,
            "agentName": "Risk Whisperer",
            "seatNumber": 6,
            "status": "Active",
            "holeCards": ["2s", "2c"],
        },
    ]
    if extra_active:
        seats.append(
            {
                "agentId": "third-id",
                "agentName": "Third",
                "seatNumber": 1,
                "status": "Active",
                "holeCards": ["Ac", "Kd"],
            }
        )
    snapshot = {"boardCards": ["5c", "9s", "2h", "6h", "4c"], "seats": seats}
    events = [
        {
            "sequence": 1,
            "type": "TableStarted",
            "payload": {
                "seatAssignments": [
                    {"agentId": HERO, "agentName": "Alnitak", "seatNumber": 3},
                    {"agentId": VILLAIN, "agentName": "Risk Whisperer", "seatNumber": 6},
                ]
            },
        },
        action(2, "River", HERO, "Alnitak", 3, "bet", 301),
        action(3, "River", VILLAIN, "Risk Whisperer", 6, "raise", 307),
        action(4, "River", HERO, "Alnitak", 3, "call", 503, 190, snapshot),
    ]
    return {"result": {"data": {"json": {"events": events}}}}


class TestReplayExporter(unittest.TestCase):
    def test_extracts_real_fields_and_verifier_finds_violation(self):
        candidates = exporter.extract_replay(raw_replay(), "table-1.json")
        self.assertEqual(len(candidates), 1)
        candidate = candidates[0]
        self.assertEqual(candidate["state"]["hole"], ["Jh", "Jd"])
        self.assertEqual(candidate["state"]["board"], ["5c", "9s", "2h", "6h", "4c"])
        self.assertEqual(candidate["state"]["potFacingDecision"], 503)
        self.assertEqual(candidate["state"]["call"], 190)
        self.assertEqual(candidate["source"]["replayFile"], "table-1.json")
        self.assertNotIn("replay", candidate["source"])
        self.assertEqual(
            candidate["state"]["actionTrace"],
            [
                {"street": "River", "actor": "agent", "action": "bet"},
                {"street": "River", "actor": "opponent", "action": "raise"},
            ],
        )
        self.assertTrue(policy.verify_case(candidate)["violation"])

    def test_multiway_river_is_not_exported(self):
        self.assertEqual(exporter.extract_replay(raw_replay(True), "table-1.json"), [])

    def test_no_agent_is_rejected(self):
        replay = raw_replay()
        with self.assertRaisesRegex(exporter.ReplayRejected, "ausente"):
            exporter.extract_replay(replay, "table-1.json", "Nobody")


if __name__ == "__main__":
    unittest.main()
