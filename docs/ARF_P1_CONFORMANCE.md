# ARF public reference P1 — candidate Dissent conformance campaign

Status: **independent ABI and local adapter candidate; not reviewed by Juan
Petter, not committed, not deployed, and not an ARF production integration.**

## Public source and boundary

This campaign references the Apache-2.0 public repository
[`petter2025us/arf-pattern-examples`](https://github.com/petter2025us/arf-pattern-examples)
at commit `b0282d789da01a9c3b94d9684d7945db024ebba8`.

It covers only the public reference property P1 for
`infrastructure.change` v1.0.0:

> For every proposal where `environment == "production"` and
> `blast_radius > 5`, the evaluator must not return `APPROVE`.

It does **not** describe or test ARF AI's proprietary risk engine, execution
controls, private invariants, or production behavior. The adapter is an
independent Dissent representation that its author has asked to review before
any deployment.

The canonical policy document is serialized as UTF-8 JSON with sorted keys and
no insignificant whitespace. Its keccak256 is
`0xf237d77c5db8f7b5bd7ebe92982ce3e601af319a81bfd88de4b9d860a6c677b0`.

## Campaign result

The Dissent value is binary:

```text
recompute(inputs, "")       = 0
recompute(inputs, evidence) = 1 only if P1's antecedent holds
                                and the ported evaluator returns APPROVE
recompute(inputs, evidence) = 0 otherwise
```

The campaign would use `Comparator.AtMost` and threshold `0`. A valid `1`
would be a disagreement with P1. Agreement across all tested proposals is a
narrow conformance result, not proof that ARF or the reference policy is safe.

## Independently defined ABI

All fields are static so malformed challenger bytes can be rejected without an
ABI-decoder revert becoming a payable adapter fault.

```solidity
struct Approval {
    bytes32 approver;
    bytes32 at;
}

struct ProposalEvidence {
    bytes32 action;
    bytes32 environment;
    bytes32 resourceId;
    uint256 blastRadius;
    uint256 reversibilityCode; // 0 missing, 1 REVERSIBLE, 2 COMPENSABLE, 3 IRREVERSIBLE
    Approval[2] approvals;
    uint256 approvalCount;
    uint256 changeWindowOpen;  // 0 false, 1 true
}
```

`bytes32("production")` contains the complete word `production`; `prod` is not
accepted. Approval entries remain objects with both the public `approver` and
`at` fields. They are not replaced by a bare count.

## Deliberate domain differences

The Python reference accepts values that cannot all fit in one bounded EVM
transaction. This candidate campaign therefore covers a declared projection:

- `blastRadius` is `uint256`, not an arbitrary-size Python integer;
- strings must fit in 32 UTF-8 bytes;
- at most two approval objects are accepted, matching the public 36-case
  conformance matrix's `0 / 1 / 2` truthiness cases;
- only outcome parity is compared; reason text and audit hashes are excluded.

These limits must be reviewed before deployment. They must not be described as
full equivalence with every value Python can represent.

## Tests required before review

- the 36 public combinations: three radii above the ceiling, four
  reversibility states, and zero/one/two approval objects;
- exact boundary: radius `5` may approve, radius `6` must not;
- full word `production`; reject `prod`;
- preserve approval object shape and reject non-canonical unused slots;
- irreversible action override, unknown environment, staging, missing
  reversibility, approval and change-window branches;
- arbitrary fixed-length evidence must never make `validateEvidence` revert;
- a valid conforming challenge returns `0` and leaves the campaign open.

## Review gate

Before any commit to `master` or deployment, send the ABI, adapter and tests to
Juan Petter. A review confirms only that this bounded public representation is
faithful to P1; it does not imply endorsement, adoption, audit, partnership, or
coverage of private ARF systems.
