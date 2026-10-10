# Kanmani and Dissent completed Mainnet case

On 10 October 2026, Kanmani and Alnitak completed a coordinated Aqueous early-release challenge on Monad Mainnet, chain 143. This is a second domain demonstration, separate from the poker replay. Both parties confirmed the result in [PR 7](https://github.com/alnitak34/dissent/pull/7#issuecomment-6094099779).

## Rule and responsibilities

The committed rule was that none of the listed flat USDC jobs would pay the named agent before an onchain delivery record. Kanmani controlled the buyer and agent and deliberately released payment early. Asuran contributed the Aqueous recomputer, tests and demo scripts; Dissent reviewed the integration and Alnitak signed the challenger operations from a separate wallet. [Implementation and review](https://github.com/alnitak34/dissent/pull/7).

This is not a discovered exploit or evidence of agent misconduct. It checks a recorded delivery condition, not the quality or completion of real-world work. It does not establish customer demand or an external audit. The delivery-first control remains a separate proposed case. [Agreed scope](https://github.com/alnitak34/dissent/pull/7#issuecomment-6094086081).

## Identifiers

- Core: `0x9D673a8B5EfE76D42593b45972Fa0426648967E1`
- Recomputer: `0x4d1A62869D16AB2Bac95408445129C4927f88457`
- Aqueous: `0xd75f7786D0DD42c8F161Bd78E87D37001044Fc32`
- Policy: `0x52655800591f954bb48cfd67e41475ec394898cd8e2e1cd8a7fa3350f7c479f8`
- Job: `0xdc15688f9f255d9c836b2e0aed854247a29f44b6cf85b6d52b949d5bf82e8234`
- Commitment: `0x39cc82c881281f204b397f10ac173df54afc9d77e5f6385195c717e32e4aed8a`
- Challenger: `0x00cf6ceC697E3DCB88a5972Ef083B423dfC00A02`

Sources: [commitment and release](https://github.com/alnitak34/dissent/pull/7#issuecomment-6093953279), [challenger receipts](https://github.com/alnitak34/dissent/pull/7#issuecomment-6094086081). Receipts and contract reads were also checked directly using `https://rpc.monad.xyz` during execution.

## Mainnet receipts

| Operation | Block | Receipt |
| --- | --- | --- |
| Commit 0.75 MON bounty | 112091732 | [Commit](https://monadvision.com/tx/0xc6cb96c6e8d7b7d81193ffe6b94faaf743c6c89ffceb4775115a23ba1a9b1ee9) |
| Early release of 0.10 USDC | 112091768 | [Release](https://monadvision.com/tx/0x654e8d70f57fa6640eecb893cbf5f737a113db4bea7c4447f02acb10b2e9e91e) |
| Seal 0.10 MON deposit | 112092838 | [Seal](https://monadvision.com/tx/0x1f514e1254f47bc5947f4c9eb86f609013ab38d0d3db567fba59dde7bd502758) |
| Reveal succeeds, value 1 against threshold 0 | 112094390 | [Reveal](https://monadvision.com/tx/0x005fafd9cd2dac481ce8bcfab5b44b00bca1e4d429b3d673bc35e703a48e6f42) |
| Withdraw 0.85 MON | 112095190 | [Withdrawal](https://monadvision.com/tx/0x76525e54404a680d50e1ecdf7f3e0c4836684eb5831c98da7fcdcda92b42be53) |

All five receipts had status 1. After release, the job read state 3 with deliveredAt 0. After reveal, the seal was settled and challenger credit was 850000000000000000 wei. After withdrawal, credit was zero. These are completion-time observations, not a continuous monitoring claim.

## Challenger costs

Calculated from each receipt's gasUsed multiplied by effectiveGasPrice:

- Seal: 0.017569431 MON.
- Reveal: 0.2472 MON.
- Withdrawal: 0.0103 MON.
- Total: 0.275069431 MON.

The 0.85 MON received includes the original 0.10 MON deposit. The calculated net for these three challenger operations is 0.474930569 MON (0.75 bounty minus gas). This excludes registration, agent/buyer costs, development time and any exchange-rate changes. It is not a profitability forecast.

The wallet changed the seal's prepared gas parameters: actual fee stayed below 0.02 MON, but its maximum possible fee became 0.024904242 MON. Subsequent reveal and withdrawal limits were checked in the wallet before signature. Do not assume browser-wallet fees preserve CLI settings.
