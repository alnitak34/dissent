# Dissent / Kanmani: internal MON settlement review

Reviewed on 15 October 2026. This note documents a focused compatibility review, not an external security audit or a live Sclera integration.

Update, 16 October 2026: Kanmani adopted the receipt mapping in its production
atlas. An independent re-run at `a00f1d2` passed 76 tests, with zero failures and
four database-dependent skips, including the two live historical withdrawals.
See [adoption and reproduction details](./kanmani-parser-proposal.md).

## Finding and correction

Two historical DissentCore withdrawals paid their challenger through internal native-token CALLs. The outer transactions called DissentCore with zero native value. At Kanmani commit [6da2937](https://github.com/zkasuran/kanmani/blob/6da29374c1cf8f70750a189668a7d958eb893175/verifier/src/rpc.ts), its reader exposed only that outer transaction's destination and value. Our local reproduction returned `settled: false` for both successful payouts.

Asuran implemented the correction in [4246520](https://github.com/zkasuran/kanmani/commit/42465204582dcadb7701bc6d2bd7e8ca734a71f5). The reader now includes internal native transfers from a call trace. Failed call subtrees do not count. If a transaction has calldata and the required trace cannot be read, the outcome is `unknown`, not a claim that no payment occurred. See the [reader](https://github.com/zkasuran/kanmani/blob/42465204582dcadb7701bc6d2bd7e8ca734a71f5/verifier/src/rpc.ts) and [settlement logic](https://github.com/zkasuran/kanmani/blob/42465204582dcadb7701bc6d2bd7e8ca734a71f5/verifier/src/ladder/settled.ts).

## Independent re-run

We checked out the correction in an isolated copy of Kanmani and ran:

```powershell
$env:RPC_MONAD = 'https://rpc.monad.xyz'
node --use-system-ca --experimental-strip-types --test src/ladder/settled.test.ts src/ladder/settled-internal.test.ts
```

Result: **40 passed, 0 failed, 4 skipped**. The skipped tests require a database. Both live withdrawal tests passed through the real reader. The internal-transfer unit test separately asserts `amountCompared: true`. The tests are [published here](https://github.com/zkasuran/kanmani/blob/42465204582dcadb7701bc6d2bd7e8ca734a71f5/verifier/src/ladder/settled-internal.test.ts).

| Monad Mainnet fixture | Exact total transferred | Transaction |
|---|---:|---|
| D-001 | 3.10 MON | [Withdrawal](https://monadvision.com/tx/0xf2378b1d2b3bb6420c0894c6d760576c35adb393bc71d0fce69852a4ddf8e336) |
| Aqueous collaboration | 0.85 MON | [Withdrawal](https://monadvision.com/tx/0x76525e54404a680d50e1ecdf7f3e0c4836684eb5831c98da7fcdcda92b42be53) |

Both pay from DissentCore `0x9d673a8b5efe76d42593b45972fa0426648967e1` to challenger `0x00cf6cec697e3dcb88a5972ef083b423dfc00a02`. Totals include the returned deposit; they are not net profit.

## Proposed receipt format

The [fixtures](./kanmani-receipt-fixtures.json) use `amountAtomic` for the exact total transferred in native atomic units. A reward/deposit split is deliberately omitted: the payment alone does not verify that split.

Proposed mapping for agreement with Kanmani:

| Receipt field | Kanmani claim field |
|---|---|
| `chainId` | `network` |
| `txHash` | `txHash` |
| `recipient` | `recipient` |
| `core` | `payer` |
| `amountAtomic` | `amount` |
| `asset` | `token` |

The mapping was not implemented at the original correction commit, but was subsequently adopted in `bcc06e2` and revalidated at `a00f1d2`. These are historical compatibility fixtures, not newly published ERC-8004 feedback and not eligible post-bond samples. No bond effectiveness is claimed.

## Next integration gates

1. Completed: agree and test the parser mapping against fixture bytes, then revalidate upstream adoption. See the linked adoption note above.
2. Define the challenger identity, the target agent receiving feedback, and legitimate future payment claims. Do not describe a wallet or this review as an autonomous service.
3. Check the deployed registry and ownership, feedback URI/hash requirements, and the live Sclera contract before preparing any transaction.
4. Obtain approval of exact bond parameters, token allowance and maximum gas. The entire bond is at risk; gas is additional. A proposed 0.01 USDC bond is not a total-cost ceiling.

## Not independently verified

- Deployment of this correction on the hosted website or sweep machine; Asuran reported deployment, but this review tested the pinned checkout.
- Asuran's mutation-testing results; we did not repeat those runs.
- Current external bond count or live slashing history.
- Deployment/source correspondence, registration status and economics for a new bond.

No registration, feedback publication, token approval, bond or financial transaction was performed during this review.
