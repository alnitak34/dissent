# -*- coding: utf-8 -*-
"""Convierte un estado candidato en los bytes canónicos del bounty de política.

Solo usa la biblioteca estándar y los módulos locales auditables del bridge.
No firma, no transmite y no necesita una wallet.
"""

import argparse
import json

import mano
import policy_bounty
import policy_spec


RECOMPUTE_GAS_LIMIT = 20_000_000
VALIDATE_GAS_LIMIT = 100_000
MAX_EVIDENCE_LEN = 160
ACTION = "Alnitak River Safety Reference v1"

_STREET = {"Preflop": 0, "Flop": 1, "Turn": 2, "River": 3}
_ACTOR = {"agent": 0, "opponent": 1}
_ACTION = {"bet": 0, "raise": 1, "all-in": 2}


def _uint_word(value, bits=256):
    if not isinstance(value, int) or value < 0 or value >= 1 << bits:
        raise ValueError("value does not fit uint%d: %r" % (bits, value))
    return value.to_bytes(32, "big")


def _fixed_word(value, size):
    if not isinstance(value, bytes) or len(value) != size:
        raise ValueError("expected bytes%d" % size)
    return value + bytes(32 - size)


def _hex_bytes(value, size, name):
    if not isinstance(value, str):
        raise ValueError("%s must be hex text" % name)
    text = value[2:] if value.startswith("0x") else value
    try:
        raw = bytes.fromhex(text)
    except ValueError as exc:
        raise ValueError("%s is not valid hex" % name) from exc
    if len(raw) != size:
        raise ValueError("%s must be %d bytes" % (name, size))
    return raw


def encode_policy_inputs(spec_document):
    digest = policy_spec.policy_hash(spec_document)
    origin = _hex_bytes(spec_document["originCommit"], 20, "originCommit")
    margin = int(spec_document["mandate"]["marginBp"])
    return _fixed_word(digest, 32) + _fixed_word(origin, 20) + _uint_word(margin, 16)


def card_byte(card_text):
    rank, suit = policy_bounty.card(card_text)
    return rank * 4 + suit


def trace_byte(event):
    try:
        street = _STREET[event["street"]]
        actor = _ACTOR[event["actor"]]
        action = _ACTION[event["action"]]
    except (KeyError, TypeError) as exc:
        raise ValueError("trace event is outside the canonical grammar") from exc
    return street | (actor << 2) | (action << 3)


def encode_evidence(case_document):
    # Validation is deliberately performed before encoding. Invalid domain
    # objects must not become challenger bytes that could be mistaken for proof.
    policy_bounty.verify_case(case_document)
    state = case_document["state"]
    cards = bytes(card_byte(c) for c in state["hole"] + state["board"])
    trace = bytes(trace_byte(event) for event in state["actionTrace"])
    if len(trace) > 8:
        raise ValueError("trace has more than eight aggressive events")
    trace_padded = trace + bytes(8 - len(trace))
    return b"".join(
        (
            _fixed_word(cards, 7),
            _uint_word(int(state["potFacingDecision"]), 64),
            _uint_word(int(state["call"]), 64),
            _fixed_word(trace_padded, 8),
            _uint_word(len(trace), 8),
        )
    )


def wad(value):
    return value.numerator * 10**18 // value.denominator


def build(case_document, spec_document):
    result = policy_bounty.verify_case(case_document)
    inputs = encode_policy_inputs(spec_document)
    evidence = encode_evidence(case_document)
    return {
        "case": case_document["case"],
        "policySpecHash": "0x" + policy_spec.policy_hash(spec_document).hex(),
        "inputs": "0x" + inputs.hex(),
        "inputsLength": len(inputs),
        "inputsHash": "0x" + mano.keccak256(inputs).hex(),
        "evidence": "0x" + evidence.hex(),
        "evidenceLength": len(evidence),
        "verdict": {
            "oldEquityWad": wad(result["oldEquity"]),
            "conditionedEquityWad": wad(result["conditionedEquity"]),
            "thresholdWad": wad(result["threshold"]),
            "violation": result["violation"],
        },
        "commit": {
            "threshold": 0,
            "comparator": "AtMost",
            "action": ACTION,
            "recomputeGasLimit": RECOMPUTE_GAS_LIMIT,
            "validateGasLimit": VALIDATE_GAS_LIMIT,
            "maxEvidenceLen": MAX_EVIDENCE_LEN,
        },
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("case", help="JSON candidate in policy-bounty fixture format")
    parser.add_argument("--spec", default=policy_spec.default_path())
    args = parser.parse_args()
    output = build(policy_bounty.load(args.case), policy_spec.load(args.spec))
    print(json.dumps(output, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
