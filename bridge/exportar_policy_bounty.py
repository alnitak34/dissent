# -*- coding: utf-8 -*-
"""Convierte replays crudos de arena.dev.fun en candidatos de policy bounty.

El exportador no decide qué mano es un contraejemplo. Solo reconstruye estados
de river observables en los que Alnitak pagó una apuesta, y luego delega el
veredicto a ``policy_bounty``. Si falta un dato, rechaza el caso: nunca lo
rellena ni usa el resultado de la mano para decidir.
"""

import argparse
import json
import os
import re

import policy_bounty


INACTIVE = {"folded", "out", "sittingout", "sitting-out", "empty", "busted"}
AGGRESSIVE = {"bet", "raise", "all-in", "allin"}
POSTFLOP = {"Flop", "Turn", "River"}
EQ_RE = re.compile(r"(?:^|\s)eq(\d+)(?:\s|:|$)", re.IGNORECASE)


class ReplayRejected(ValueError):
    """El replay no pertenece al dominio canónico o carece de evidencia."""


def _unwrap(replay):
    value = replay
    for key in ("result", "data", "json"):
        if isinstance(value, dict) and key in value:
            value = value[key]
    if not isinstance(value, dict) or not isinstance(value.get("events"), list):
        raise ReplayRejected("events ausente")
    return value


def _call_amount(payload):
    allowed = payload.get("allowedActions") or {}
    for value in (
        allowed.get("callChips"),
        allowed.get("callAmount"),
        payload.get("callAmount"),
        payload.get("amount"),
    ):
        if value is not None:
            amount = int(value)
            if amount > 0:
                return amount
    raise ReplayRejected("callAmount positivo ausente")


def _hero_cards(event, hero_id):
    snapshot = event.get("snapshot") or {}
    board = list(snapshot.get("boardCards") or [])
    if len(board) != 5:
        raise ReplayRejected("board de river incompleto")
    seats = snapshot.get("seats") or []
    hero = next((seat for seat in seats if seat.get("agentId") == hero_id), None)
    if hero is None:
        seat_no = (event.get("payload") or {}).get("seatNumber")
        hero = next((seat for seat in seats if seat.get("seatNumber") == seat_no), None)
    hole = list((hero or {}).get("holeCards") or [])
    if len(hole) != 2:
        raise ReplayRejected("holeCards del agente ausentes")
    return hole, board, seats


def _active_opponent(seats, hero_id):
    active = [
        seat for seat in seats
        if str(seat.get("status", "")).lower() not in INACTIVE
    ]
    if len(active) != 2:
        raise ReplayRejected("la decisión no era heads-up")
    opponents = [seat for seat in active if seat.get("agentId") != hero_id]
    if len(opponents) != 1 or not opponents[0].get("agentId"):
        raise ReplayRejected("oponente activo no identificable")
    return opponents[0]["agentId"]


def _trace(events, before_sequence, hero_id, opponent_id):
    trace = []
    for event in events:
        if int(event.get("sequence") or -1) >= before_sequence:
            continue
        if event.get("type") != "ActionTaken" or event.get("street") not in POSTFLOP:
            continue
        actor_id = event.get("agentId")
        if actor_id not in (hero_id, opponent_id):
            continue
        action = str((event.get("payload") or {}).get("action", "")).lower()
        if action not in AGGRESSIVE:
            continue
        trace.append(
            {
                "street": event["street"],
                "actor": "agent" if actor_id == hero_id else "opponent",
                "action": "all-in" if action in ("all-in", "allin") else action,
            }
        )
    if not trace:
        raise ReplayRejected("traza agresiva vacía")
    if len(trace) > 8:
        raise ReplayRejected("traza supera el máximo canónico de 8 eventos")
    return trace


def _hero_ids(events, hero_name):
    wanted = hero_name.casefold()
    found = set()
    for event in events:
        payload = event.get("payload") or {}
        if str(payload.get("agentName", "")).casefold() == wanted and event.get("agentId"):
            found.add(event["agentId"])
        if event.get("type") == "TableStarted":
            for seat in payload.get("seatAssignments") or []:
                if str(seat.get("agentName", "")).casefold() == wanted and seat.get("agentId"):
                    found.add(seat["agentId"])
    return found


def extract_replay(replay, source_path, hero_name="Alnitak"):
    """Devuelve candidatos válidos; una mesa puede contener cero o más."""
    data = _unwrap(replay)
    events = sorted(data["events"], key=lambda event: int(event.get("sequence") or -1))
    hero_ids = _hero_ids(events, hero_name)
    if not hero_ids:
        raise ReplayRejected("agente %r ausente" % hero_name)

    candidates = []
    for event in events:
        payload = event.get("payload") or {}
        hero_id = event.get("agentId")
        if (
            event.get("type") != "ActionTaken"
            or event.get("street") != "River"
            or str(payload.get("action", "")).lower() != "call"
            or hero_id not in hero_ids
        ):
            continue
        sequence = int(event.get("sequence"))
        try:
            call = _call_amount(payload)
            pot = int(payload.get("pot"))
            if pot <= 0:
                raise ReplayRejected("pot positivo ausente")
            hole, board, seats = _hero_cards(event, hero_id)
            opponent_id = _active_opponent(seats, hero_id)
            trace = _trace(events, sequence, hero_id, opponent_id)
            candidate = {
                "case": "historical-%s-%s" % (
                    os.path.splitext(os.path.basename(source_path))[0], sequence
                ),
                "source": {
                    "tableId": os.path.splitext(os.path.basename(source_path))[0],
                    "sequence": sequence,
                    "agentId": hero_id,
                    # No incrustar la ruta local de quien ejecuta el exportador.
                    # tableId + sequence bastan para recuperar/verificar la fuente.
                    "replayFile": os.path.basename(source_path),
                },
                "state": {
                    "street": "River",
                    "hole": hole,
                    "board": board,
                    "potFacingDecision": pot,
                    "call": call,
                    "actionTrace": trace,
                    "action": "call",
                },
                "policy": {"marginBp": 1500},
            }
            reasoning = str(payload.get("reasoning") or "")
            match = EQ_RE.search(reasoning)
            if match:
                candidate["historical"] = {
                    "reportedOldEquityPercent": int(match.group(1))
                }
            # La misma validación pública que usará el scanner. Esto elimina
            # trazas incompletas o fuera del dominio sin conocer el resultado.
            policy_bounty.verify_case(candidate)
            candidates.append(candidate)
        except (KeyError, TypeError, ValueError, ReplayRejected):
            continue
    return candidates


def replay_paths(paths):
    found = []
    for path in paths:
        if os.path.isdir(path):
            for root, _, names in os.walk(path):
                found.extend(
                    os.path.join(root, name)
                    for name in names
                    if name.lower().endswith(".json")
                )
        elif path.lower().endswith(".json"):
            found.append(path)
    return sorted(set(os.path.abspath(path) for path in found))


def export(paths, hero_name="Alnitak"):
    report = {"replays": 0, "unreadable": 0, "candidates": [], "counterexamples": []}
    for path in replay_paths(paths):
        report["replays"] += 1
        try:
            with open(path, encoding="utf-8") as handle:
                candidates = extract_replay(json.load(handle), path, hero_name)
        except (OSError, json.JSONDecodeError, ReplayRejected):
            report["unreadable"] += 1
            continue
        for candidate in candidates:
            result = policy_bounty.verify_case(candidate)
            report["candidates"].append(candidate)
            if result["violation"]:
                report["counterexamples"].append(
                    {
                        "case": candidate["case"],
                        "source": candidate["source"],
                        "hole": candidate["state"]["hole"],
                        "board": candidate["state"]["board"],
                        "oldEquity": "%d/%d" % (
                            result["oldEquity"].numerator,
                            result["oldEquity"].denominator,
                        ),
                        "conditionedEquity": "%d/%d" % (
                            result["conditionedEquity"].numerator,
                            result["conditionedEquity"].denominator,
                        ),
                        "threshold": "%d/%d" % (
                            result["threshold"].numerator,
                            result["threshold"].denominator,
                        ),
                    }
                )
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="+", help="replay JSON files or directories")
    parser.add_argument("--hero", default="Alnitak", help="agentName exacto")
    parser.add_argument("--output", help="directorio donde guardar candidatos válidos")
    args = parser.parse_args()
    report = export(args.paths, args.hero)
    if args.output:
        os.makedirs(args.output, exist_ok=True)
        for candidate in report["candidates"]:
            target = os.path.join(args.output, candidate["case"] + ".json")
            with open(target, "w", encoding="utf-8", newline="\n") as handle:
                json.dump(candidate, handle, indent=2, ensure_ascii=False)
                handle.write("\n")
    summary = {
        "replays": report["replays"],
        "unreadable": report["unreadable"],
        "validCandidates": len(report["candidates"]),
        "counterexamples": report["counterexamples"],
    }
    print(json.dumps(summary, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
