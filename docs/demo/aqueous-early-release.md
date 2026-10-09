# Coordinated demonstration: Aqueous early release

Question: "Was this agent paid before an onchain delivery record existed?" Aqueous holds the escrow record, `AqueousFlatDeliveryRecomputer` checks the condition and Dissent handles the bounty and the challenge.

This is a coordinated example. Buyer and agent are run by the same operator (Kanmani). The buyer releases early on purpose. A successful challenge here is not a discovered exploit and not evidence of agent misconduct. Public terms: [aqueous-early-release.terms.txt](aqueous-early-release.terms.txt), keccak256 of the file bytes `0x6661ad444cb7963a313a077b89755439c73b96fc48a459bedeb52b42c1057db7`.

## Parameters

| | |
|---|---|
| Recomputer | `0x4d1A62869D16AB2Bac95408445129C4927f88457` (Sourcify verified) |
| Policy | deposit 0.1 MON, recompute 1,500,000, validate 200,000, maxEvidenceLen 32 |
| Policy id | `0x52655800591f954bb48cfd67e41475ec394898cd8e2e1cd8a7fa3350f7c479f8` |
| Agent | `0xDB6c6340342e71A63cD11Ebac2185204b7777777` (Kanmani house wallet) |
| Buyer | `0x27a8ae37f59BDcd147b09dDc1F35Ac64697c1F92` (Kanmani demo buyer) |
| Challenger | to be confirmed by Alnitak; the rehearsal uses a test-only placeholder |
| Job | flat, 0.10 USDC, deadline 3 days after opening |
| Job salt | `keccak256("kanmani.dissent.demo.aqueous-early-release.v1")` |
| Job id | `0xdc15688f9f255d9c836b2e0aed854247a29f44b6cf85b6d52b949d5bf82e8234` (fixed by buyer, agent and salt) |
| Claim | inputs `abi.encode(agent, [jobId])`, threshold 0, `AtMost`, window 2 hours |
| Bounty | 0.5 MON |
| Evidence | `abi.encode(uint256(0))` |

## Steps

Each step is one participant's single transaction in [script/AqueousEarlyReleaseDemo.s.sol](../../script/AqueousEarlyReleaseDemo.s.sol). Without `--broadcast` forge only simulates.

| # | Signer | Contract |
|---|---|---|
| 0 | agent | plain transfer of 0.1 MON to the buyer for gas |
| 1 | curator | `DemoRegisterPolicy` |
| 2 | buyer | `DemoBuyerApprove` |
| 3 | buyer | `DemoBuyerOpenJob` |
| 4 | agent | `DemoAgentCommit` (checks the base is 0) |
| 5 | buyer | `DemoBuyerReleaseEarly` (checks the agent received 0.10 USDC) |
| 6 | challenger | `DemoChallengerSeal` |
| 7 | challenger | `DemoChallengerReveal`, at least 5 blocks after the seal |
| 8 | challenger | `DemoChallengerWithdraw` |

Environment: `DEMO_AGENT`, `DEMO_BUYER`, `DEMO_CHALLENGER`, `DEMO_REWARD_WEI`, `DEMO_JOB_SALT`, `DEMO_AGENT_SALT` (agent only), `DEMO_CHALLENGER_SALT` (challenger only), `DEMO_COMMITMENT_ID` (from the `Committed` event, after step 4). One step, simulated only:

```text
forge script script/AqueousEarlyReleaseDemo.s.sol:DemoBuyerOpenJob --rpc-url https://rpc.monad.xyz --sender 0x27a8ae37f59BDcd147b09dDc1F35Ac64697c1F92
```

## Fork rehearsal

```text
MONAD_RPC_URL=<Monad RPC> script/demo/rehearse-aqueous-early-release.sh
```

It forks Monad mainnet at block 111,847,000 with anvil, impersonates every signer and runs steps 0 to 8 against the fork only. Funding for the curator and the placeholder challenger is fork-only test balance. The challenger is `address(uint160(uint256(keccak256("dissent.demo.challenger.TEST-ONLY-PLACEHOLDER"))))`, which no one holds a key for; every step refuses it unless `DEMO_REHEARSAL=true`.

Result with Foundry 1.8.1: base value 0 at commit, the agent received 100,000 USDC units on early release, recompute with evidence returned 1, the reveal ended `Challenged` and the challenger withdrew 0.6 MON. The job ends Settled and the challenger credit at 0.

Gas. Monad charges the gas limit, so the cost column uses the limit forge set (its estimate plus 30%), at 102 gwei:

| Step | Used | Limit | MON |
|---|---:|---:|---:|
| 0 agent tops up buyer | 21,000 | 21,000 | 0.0021 |
| 1 curator registers | 109,674 | 142,576 | 0.0145 |
| 2 buyer approves | 86,704 | 113,454 | 0.0116 |
| 3 buyer opens job | 242,830 | 318,466 | 0.0325 |
| 4 agent commits | 354,732 | 463,993 | 0.0473 |
| 5 buyer releases | 136,401 | 180,170 | 0.0184 |
| 6 challenger seals | 110,662 | 146,715 | 0.0150 |
| 7 challenger reveals | 153,150 | 2,919,161 | 0.2978 |
| 8 challenger withdraws | 69,310 | 92,957 | 0.0095 |

The reveal limit is high because DissentCore requires enough gas for both capped calls (`txRequired` 2,278,568). At that limit it would cost about 0.232 MON; a reveal sent with exactly that limit was not rehearsed. The minimum gas-backed reward at commit was 0.2479 MON. With a 0.5 MON bounty the challenger nets roughly 0.18 to 0.24 MON after its three transactions.
