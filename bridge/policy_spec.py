# -*- coding: utf-8 -*-
"""Canonicaliza y calcula la identidad Ethereum de una política Dissent."""

import json
import os

import mano


def canonical_bytes(document):
    return json.dumps(
        document,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")


def load(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def policy_hash(document):
    return mano.keccak256(canonical_bytes(document))


def default_path():
    return os.path.abspath(
        os.path.join(
            os.path.dirname(__file__),
            "..",
            "docs",
            "policies",
            "alnitak-river-safety-v1.json",
        )
    )


if __name__ == "__main__":
    path = default_path()
    print(path)
    print("0x" + policy_hash(load(path)).hex())
