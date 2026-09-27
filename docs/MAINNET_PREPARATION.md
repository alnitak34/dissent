# Monad Mainnet preparation — Dissent

Status: **preparation only**. Nothing in this document proves that Dissent has
been deployed on Mainnet. Do not broadcast until the dry-run cost is recorded
and Julieth explicitly approves that maximum cost.

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

This snapshot used the official public RPC, chain ID `143`, a dummy unfunded
sender and no wallet configuration. No transaction was transmitted.

Foundry reported:

```text
Estimated base fee:         100 gwei
Estimated priority fee:       2 gwei
Estimated max fee:          202 gwei
Total declared gas:   6,349,715
Maximum amount required: 1.28264243 MON
```

Per operation, from the generated dry-run artifact:

| Operation | Gas limit | Maximum at 202 gwei |
| --- | ---: | ---: |
| Deploy `AlnitakPolicyBountyRecomputer` | 2,638,304 | 0.532937408 MON |
| Deploy `RecomputerRegistry` | 773,662 | 0.156079724 MON |
| `registerPolicy(...)` | 30,912 | 0.006244224 MON |
| Deploy `DissentCore` | 2,906,837 | 0.587381074 MON |
| **Total** | **6,349,715** | **1.282642430 MON** |

The `202 gwei` column is the conservative max-fee amount Foundry required for
the simulation, not a prediction of the final effective fee. A later dry-run
must replace this snapshot immediately before any broadcast.

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
