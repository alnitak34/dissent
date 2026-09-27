# Monad Mainnet deployment record — Dissent

Status: **deployment complete and source-verified on 2026-09-27**. The three
contracts and the policy registration are live on Monad Mainnet. This record
does **not** claim a complete Mainnet challenge cycle: commitment, seal, reveal,
settlement and withdrawal remain pending and require separate approvals.

## Current architecture

Mainnet is a new deployment, not a migration. The verified Testnet contracts
and public replay remain unchanged. The current release requires three
contracts and one policy-registration transaction:

1. `AlnitakPolicyBountyRecomputer`
2. `RecomputerRegistry`
3. `RecomputerRegistry.registerPolicy(...)`
4. `DissentCore`, constructed with the registry address

The historical `mainnet-prep` branch predates the registry and must not be
broadcast. It deploys only two contracts and calls an obsolete core constructor.

## Official network facts

- Network: Monad Mainnet
- Chain ID: `143`
- Public RPC used for the preflight: `https://rpc.monad.xyz`
- Currency: `MON`
- Per-transaction gas limit: `30,000,000`
- Monad charges `gas_limit * gas_price`, not gas actually consumed.
- Minimum base fee documented by Monad: `100 MON-gwei`.
- Foundry requirement: `>= 1.8.0` with the Monad execution network enabled.

Sources:

- <https://docs.monad.xyz/developer-essentials/network-information>
- <https://docs.monad.xyz/developer-essentials/summary>
- <https://docs.monad.xyz/developer-essentials/gas-pricing>

At the documented minimum base fee, a transaction declaring the full 30M gas
limit costs **3 MON before priority fee**. This is a ceiling example, not the
expected cost of this deployment. The decision must use fresh dry-run gas limits
and current fees.

## Inputs kept outside Git

Deployment reads only the public curator address from the environment:

```text
DISSENT_MAINNET_CURATOR
```

The key or mnemonic is never stored in this repository. The curator must be the
actual deployment signer because it performs `registerPolicy` in the same run.

The later challenge flow will additionally require public contract and wallet
addresses, the emitted `policyId`, a deliberately chosen reward, and two salts.
Salts remain local and private until their corresponding reveal.

```text
DISSENT_MAINNET_CORE
DISSENT_MAINNET_REGISTRY
DISSENT_MAINNET_RECOMPUTER
DISSENT_MAINNET_POLICY_ID
DISSENT_MAINNET_AGENT
DISSENT_MAINNET_CHALLENGER
DISSENT_MAINNET_REWARD_WEI
DISSENT_AGENT_SALT
DISSENT_CHALLENGER_SALT
DISSENT_COMMITMENT_ID
```

`PolicyBountyMainnetFlow.s.sol` separates commit, challenge commit, challenge
reveal and withdrawal. Each run can produce at most one transaction and checks
the registry policy, immutable code hash, expected signer and recorded state
before broadcasting. The challenge-commit phase also rejects a closed
commitment window or an existing live seal locally, before Foundry can submit a
transaction. Withdrawal accepts an accumulated challenger credit only when it
is at least the reward plus this campaign's deposit, and logs the full amount
that `withdrawCredit()` will transfer.

## Preflight sequence

1. Freeze the exact release commit.
2. Run formatting, the full suite, lint and contract-size checks.
3. Read `eth_chainId` from the RPC and require `143`.
4. Run `DeployPolicyBountyMainnet` without `--broadcast`.
5. Record all four transaction gas limits and the maximum MON cost Foundry shows.
6. Confirm the dedicated curator/agent and challenger public addresses and balances.
7. Obtain explicit approval for the measured maximum deployment cost.
8. Broadcast only the deployment package.
9. Verify all three sources and inspect the policy-registration receipt.
10. Read every post-deploy invariant and `minGasBackedReward` onchain.
11. Dry-run each challenge-flow phase separately and disclose its maximum cost.
12. Obtain separate approval before each Mainnet financial action.
13. Update the website to Mainnet only after a complete verified settlement and withdrawal.

## Dry-run command

PowerShell, with the curator public address already set locally:

```powershell
forge script script/DeployPolicyBountyMainnet.s.sol:DeployPolicyBountyMainnet --rpc-url https://rpc.monad.xyz --sender $env:DISSENT_MAINNET_CURATOR
```

This command intentionally omits `--broadcast`. Addresses printed by the
simulation are not Mainnet deployment addresses.

## Recorded dry-run — 2026-09-27

This final pre-broadcast snapshot used the official public RPC, chain ID `143`,
the intended curator address and no signing key. No transaction was transmitted
by the dry-run.

Foundry reported:

```text
Estimated base fee:         100 gwei
Estimated priority fee:       2 gwei
Estimated max fee:          202 gwei
Total estimated gas:  6,349,998
Maximum amount required: 1.282699596 MON
```

Per operation, from the generated dry-run artifact:

| Operation | Gas limit | Maximum at 202 gwei |
| --- | ---: | ---: |
| Deploy `AlnitakPolicyBountyRecomputer` | 2,638,304 | 0.532937408 MON |
| Deploy `RecomputerRegistry` | 773,945 | 0.156336890 MON |
| `registerPolicy(...)` | 30,912 | 0.006244224 MON |
| Deploy `DissentCore` | 2,906,837 | 0.587181074 MON |
| **Total** | **6,349,998** | **1.282699596 MON** |

The `202 gwei` column is the conservative max-fee amount Foundry required for
the simulation, not a prediction of the final effective fee. The broadcast was
then capped at `202 gwei` max fee and `2 gwei` priority fee.

## Mainnet deployment — 2026-09-27

Release commit: `b69faa355f1da80555011fe31e56996419df5824`.
Tracked files matched `origin/master`; the unrelated local untracked file
`docs/RECORDING_RUNBOOK.md` was not included or modified.

| Component | Address / identifier |
| --- | --- |
| Curator and deployer | `0xa3aB9C3697F1964A8082330103C5DCaaA3B1263A` |
| `AlnitakPolicyBountyRecomputer` | `0x6dCD184c9c0db42FCD0De731F9a2855b38916758` |
| `RecomputerRegistry` | `0x2a26e33CD2118a2D340bbA810e23a8E5CfdE8E38` |
| `DissentCore` | `0x9D673a8B5EfE76D42593b45972Fa0426648967E1` |
| Policy ID | `0xd98b72f99b52f0ac912f4a6278b95ba01a1d045bf1840f58b8a77708ca61abbc` |

All four receipts returned `status = 1`:

| Operation | Transaction | Block | Declared/charged gas | Effective price | Cost |
| --- | --- | ---: | ---: | ---: | ---: |
| Deploy recomputer | `0xcd48e435961ceed6b7aafdc6c03ed71a2d24c39b46d6a116061402261c18722c` | 108,412,422 | 3,924,038 | 103 gwei | 0.404175914 MON |
| Deploy registry | `0x25bdc980be317bc0159315aa9ffbf16791fb330529f83be7f4da83d0d3419595` | 108,412,474 | 1,149,519 | 106.954442581 gwei | 0.122946163881268539 MON |
| Register policy | `0x43bf368d0ddc5243c277c3c1e14bbf208dc4f57e98c731c14484a4cb6fab49a9` | 108,412,716 | 166,211 | 103 gwei | 0.017119733 MON |
| Deploy core | `0xf16db3148fd37dbfc9922d0ebfbaf1841c3c65617fd57d4b6bcbb26d7503fbe6` | 108,413,241 | 4,360,256 | 102 gwei | 0.444746112 MON |
| **Total** |  |  | **9,600,024** |  | **0.988987922881268539 MON** |

Post-deploy reads confirmed the registry link, active policy, curator, policy
limits, `MIN_WINDOW = 3600`, `MONAD_TX_GAS_LIMIT = 30,000,000`,
`REFERENCE_GAS_PRICE = 100 gwei` and `escrowed = 0`.

## Source verification

All three submissions returned `Status: match` through the Monad-documented
Sourcify/Blockvision endpoint:

- Recomputer: [`b6c78ca3-b5f0-4cb6-82da-eb1077523525`](https://sourcify-api-monad.blockvision.org/verify-ui/jobs/b6c78ca3-b5f0-4cb6-82da-eb1077523525)
- Registry: [`1ff0aa41-33cb-487d-9013-0e376e0770df`](https://sourcify-api-monad.blockvision.org/verify-ui/jobs/1ff0aa41-33cb-487d-9013-0e376e0770df)
- Core: [`bcd83caa-7c42-4852-a7ea-cfb717b9fe1c`](https://sourcify-api-monad.blockvision.org/verify-ui/jobs/bcd83caa-7c42-4852-a7ea-cfb717b9fe1c)

Source verification proves reproducible bytecode matching. It is not an
external security audit.

## Stop conditions

- Chain ID is not exactly `143`.
- The release working tree is not clean or the commit is not recorded.
- Any transaction estimate is above 30M gas.
- The measured maximum cost has not been approved.
- The signer differs from `DISSENT_MAINNET_CURATOR`.
- Source verification or any post-deploy invariant fails.
- The onchain reward floor or actual gas economics no longer fit the chosen bounty.

No private key, seed phrase, password, secret RPC, salt or funded-wallet balance
belongs in Git, chat, screenshots or the website.
