# -*- coding: utf-8 -*-
"""Busca contraejemplos Dissent en candidatos JSON sin conocer el ganador.

El buscador no contiene cartas, mesas ni valores esperados. Solo recorre los
candidatos recibidos y aplica el verificador independiente de la política.
"""

import argparse
import json
import os

import policy_bounty


def candidate_paths(paths):
    found = []
    for path in paths:
        if os.path.isdir(path):
            for root, _, names in os.walk(path):
                found.extend(
                    os.path.join(root, name)
                    for name in names
                    if name.lower().endswith(".json")
                )
        else:
            found.append(path)
    return sorted(set(os.path.abspath(path) for path in found))


def scan(paths):
    report = {"examined": 0, "valid": 0, "rejected": [], "counterexamples": []}
    for path in candidate_paths(paths):
        report["examined"] += 1
        try:
            result = policy_bounty.verify_case(policy_bounty.load(path))
        except (KeyError, TypeError, ValueError, json.JSONDecodeError) as exc:
            report["rejected"].append({"path": path, "reason": str(exc)})
            continue
        report["valid"] += 1
        if result["violation"]:
            report["counterexamples"].append(
                {
                    "path": path,
                    "case": result["case"],
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
    parser.add_argument("paths", nargs="+", help="candidate JSON files or directories")
    args = parser.parse_args()
    report = scan(args.paths)
    print(json.dumps(report, indent=2, ensure_ascii=False))
    return 0 if report["counterexamples"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
