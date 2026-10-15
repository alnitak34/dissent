# Dissent receipt parser: review proposal

Status: proposed, not upstream, not deployed. No ERC-8004 feedback or bond has
been published by this work. Base Kanmani commit:
`42465204582dcadb7701bc6d2bd7e8ca734a71f5`.

## Files

- [Mapping](./dissent-mapping-proposal.ts)
- [Tests](./dissent-mapping-proposal.test.ts)
- [Individual receipt fixtures collected in an array](./kanmani-receipt-fixtures.json)
- [Saved trace excerpts](./kanmani-trace-excerpts.json)

Copy these four files into the `verifier/` directory of an isolated checkout
of Kanmani at the base commit. The excerpts contain the original call traces
and reduced receipt/transaction fields from our saved RPC evidence. Receipt
logs are deliberately omitted; the tests use native calls, not payment events.
They are offline replay fixtures, not newly fetched or complete RPC responses.

Install the pinned verifier dependencies without lifecycle scripts:

```
npm ci --ignore-scripts --no-audit --no-fund
node --experimental-strip-types --test dissent-mapping-proposal.test.ts src/ladder/parse.test.ts src/ladder/settled.test.ts src/ladder/settled-internal.test.ts
```

Use Node 24. With live-RPC opt-in and database variables unset, the focused
run is expected to pass 73 tests and skip 6: two live RPC tests and four
database-dependent tests. This is not a whole-repository test or security audit.

The proposal adds the mapping to a test-specific atlas only. Adoption would
require moving it into upstream source and registering it in the production
atlas; merely copying these files does not enable it in Kanmani.

## Decisions for agreement

- One receipt object per feedback URI. The fixture array is not a feedback document.
- v1 accepts only native payments on Monad chain 143, version number 1.
- `amountAtomic` is a positive integer string for the exact total transferred.
- Required fields must be present and valid; never fall back to a weaker
  transaction-exists check for an incomplete Dissent receipt.
- Reward and returned-deposit splits are not inferred from a transfer.
- `core` maps to payer metadata. Upstream settlement does not enforce the claimed
  payer, so this proposal does not certify payment provenance from that field.
- Unsupported versions/assets/chains are unparsed, not silently coerced.

The 13 proposal tests cover both saved withdrawals, altered amount and recipient,
missing traces, missing fields, invalid amounts, unsupported versions/networks/assets,
array rejection and ambiguous shapes. Historical fixtures do not count as future
post-bond activity.

## Verified / not verified

Verified locally: the focused test run, exact fixture amounts and recipients,
and offline settlement against the saved call traces. See the earlier
[settlement review](./kanmani-settlement-review.md) for the separate live re-run.

Not verified: upstream adoption of this proposal, deployment, ERC-8004 feedback
integrity/publication, prospective sample activity or the economics of a bond.

This proposal is offered for Asuran's review; he may prefer a different mapping
implementation while preserving the receipt semantics.
