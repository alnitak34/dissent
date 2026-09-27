# Metropolis submission package — Dissent

Status: **draft only**. Nothing in this file has been submitted to the
Metropolis portal. Replace every bracketed placeholder before publication.

## Project name

Dissent

## One-line description

Agents fund bounties on their own deterministic policies; anyone who proves a
committed boundary wrong gets paid on Monad.

## Short pitch

Dissent is a counterexample bounty protocol for deterministic agent policies.
An agent commits to a policy, a numerical boundary and a reward. Challengers
search for a valid state that breaks that boundary. Monad reruns the registered
policy onchain and settles the bounty without an AI judge, a vote or a trusted
operator.

## Long description

Agents increasingly produce scores, limits and recommendations that other
systems may use, but publishing a number or signing it does not make it correct.
Dissent turns a falsifiable agent policy into an open economic challenge.

The agent selects a policy from a curated registry, commits its inputs and
threshold, and escrows a reward. A challenger first seals a hidden evidence hash
and deposits collateral. After the reveal delay, the challenger discloses the
evidence. DissentCore validates it through the policy's immutable recomputer,
reruns the same deterministic rule and compares the result with the committed
boundary. A valid counterexample pays the reward and returns the deposit. A
failed challenge sends the deposit to the agent. Malformed evidence is rejected,
and technical adapter failures are classified without paying a bounty.

The recorded demonstration uses a poker policy because it supplied a real,
bounded decision rule and historical counterexample. The protocol itself has no
poker logic: another domain integrates by registering a deterministic
recomputer with bounded inputs, evidence and gas.

The demonstrated result is deliberately narrow. It proves that the challenge
mechanism, recomputation and settlement work for the recorded policy. It does
not prove that every agent output is correct, that no other counterexample
exists, that the adapter has been externally audited, or that external adoption
already exists.

## Problem

Reputation and signatures answer who produced a result. They do not answer
whether a specific numerical decision still holds when an adversary presents a
valid state the agent missed. Internal testing also gives outsiders no
independent economic route to surface that counterexample.

## Solution

Dissent funds adversarial search and keeps verification deterministic. The hard
work may be finding a counterexample; checking one concrete state is performed
by the registered recomputer on Monad. The contract binds the policy version,
code hash, evidence bounds, gas limits, threshold and money before the challenge.

## Why Monad

Dissent needs enough transaction gas to validate evidence, rerun a substantial
deterministic policy and settle value in one public execution path. Monad's EVM
compatibility lets the protocol use Solidity and standard Ethereum tooling,
while its 30 million per-transaction gas limit accommodates the measured
recomputation path. The implementation explicitly accounts for Monad's rule
that fees are charged from the declared gas limit rather than gas used.

## Working product and evidence

- Public demo: <https://dissent-henna.vercel.app/>
- Repository: <https://github.com/alnitak34/dissent> — currently private; it
  must be made public before submission.
- Track: Trust, Identity & AI Infrastructure
- Verified deployments: Monad Testnet and Monad Mainnet
- Complete recorded financial cycles: Monad Testnet and Monad Mainnet
- Mainnet evidence and receipts: see `docs/MAINNET_LIVE_RUN.md`. The public web
  deployment presents these receipts and reads their final state from Monad.
- Source verification, contract addresses and transaction receipts must be
  linked directly in the final submission.

## Deliverable audit

| Deliverable | Current evidence | Status / next action |
| --- | --- | --- |
| Project identity | `Dissent`; logo at `web/assets/dissent-mark-1024.png` | Ready |
| One-line description | Draft above | Ready for final language review |
| Long description | Draft above | Ready for final language review |
| Live product | <https://dissent-henna.vercel.app/> | Working Mainnet replay; run the final mobile/desktop factual audit before capture |
| Code link | <https://github.com/alnitak34/dissent> | Private; make public before submission and keep public as required by the rules |
| Public video | No final video URL recorded | Record and upload one video, maximum 3 minutes |
| Onchain evidence | Complete Mainnet commit, seal, successful reveal and withdrawal; source-verified deployment | Ready after final link audit |

## Evidence to show, not merely claim

- Current registry-based Testnet deployment:
  `DissentCore 0x686164f708b87d1A63bEE8Aa3130298246690a87`,
  `RecomputerRegistry 0xD92a8aa9C28168484abB6D03eC261DD1FC1b0B9b`, and
  `AlnitakPolicyBountyRecomputer 0xaC87125846C19A978B3D847a9E49Dd7744aa6880`.
- Active policy ID:
  `0xd50b859dbdf6d6fcd167fefb8626bc64bd44683881f58098c24612a720e09cef`.
- The replay code reads the four recorded Mainnet receipts and final commitment
  state rather than simulating an outcome locally.
- A separate Testnet transaction exercised the non-payable technical-fault
  classification. This is one concrete path, not proof that every EVM failure
  has been audited.
- Local tests and CI are engineering evidence, not an external security audit.
- Verified Mainnet deployment:
  `DissentCore 0x9D673a8B5EfE76D42593b45972Fa0426648967E1`,
  `RecomputerRegistry 0x2a26e33CD2118a2D340bbA810e23a8E5CfdE8E38`, and
  `AlnitakPolicyBountyRecomputer 0x6dCD184c9c0db42FCD0De731F9a2855b38916758`.
- Mainnet policy ID:
  `0xd98b72f99b52f0ac912f4a6278b95ba01a1d045bf1840f58b8a77708ca61abbc`.
- The three Mainnet source submissions returned `Status: match`. The complete
  Mainnet challenge and withdrawal are recorded in `docs/MAINNET_LIVE_RUN.md`.

## Mainnet statement

### Current accurate statement

Dissent is deployed on Monad Mainnet. The three contracts, policy registration,
challenge settlement and withdrawal are linked below and their final state has
been read back from chain. The challenger received the `3.1 MON` credit, then
withdrew it; final reads returned zero credit, zero escrow and zero core balance.
The route was technically successful but economically negative for the
challenger by `0.088395576 MON` after gas.

- DissentCore: `0x9D673a8B5EfE76D42593b45972Fa0426648967E1`
- RecomputerRegistry: `0x2a26e33CD2118a2D340bbA810e23a8E5CfdE8E38`
- Policy recomputer: `0x6dCD184c9c0db42FCD0De731F9a2855b38916758`
- Policy registration: `0x43bf368d0ddc5243c277c3c1e14bbf208dc4f57e98c731c14484a4cb6fab49a9`
- Agent commitment: `0x59c55bd184635cae41d2f00a56b90b5f5da07e12edef60f2642d727f0c476dd0`
- Challenge seal: `0x17e815f3f6ac6781e7981665ca741e92847a4a301771100dae15269b22321cf0`
- Challenge reveal: `0xbc121f84234ec22fc8aace845333e3b4e169c2f55776fa55f967d70317a4f529`
- Withdrawal: `0xf2378b1d2b3bb6420c0894c6d760576c35adb393bc71d0fce69852a4ddf8e336`

## Mainnet decision gate

Mainnet is a credibility signal only if the evidence is stronger than the
existing testnet record. Before any broadcast:

1. Freeze and record the exact release commit.
2. Merge only reviewed changes and require a clean working tree.
3. Run formatting, the complete suite, lint and size checks.
4. Confirm chain ID `143` from the RPC.
5. Repeat the deployment dry-run and record every transaction gas limit, the
   current fees and the maximum MON exposure.
6. Obtain explicit approval for that measured maximum cost.
7. Broadcast the deployment package, verify all three contracts and read every
   invariant back from chain.
8. Dry-run and separately approve each value-bearing phase of the challenge.
9. Complete commitment, seal, reveal and withdrawal with two dedicated roles.
10. Update the website and this package only after receipts and final state are
    independently readable.

The current dry-run in `docs/MAINNET_PREPARATION.md` is a snapshot, not a price
quote. Monad charges `gas_limit * price_per_gas`; it must be repeated immediately
before a financial decision.

## Public submission video — maximum 3 minutes

1. **Problem.** “Agents test the states they expect. Dissent funds the search
   for the state they missed.”
2. **Committed rule.** Show the policy, threshold, registered recomputer and MON
   bounty fixed before the challenge.
3. **Hidden evidence.** Explain the seal-and-reveal step without exposing salts
   or wallet secrets.
4. **Counterexample.** Reveal the recorded state and show the recomputed value
   crossing the committed boundary.
5. **Settlement.** Show `POLICY BROKEN`, the challenger credit and the withdrawal
   receipt.
6. **Verification.** Open the public contract and transaction links. State that
   source verification is not an audit.
7. **Boundary.** Poker is the first adapter; every other domain needs its own
   deterministic, reviewed recomputer.

Draft spoken script for that same video:

> Hi, I’m Julieth, and I build under the name Alnitak. While operating my poker
> agent, I found a decision that looked justified under its original model but
> failed when one valid historical state was recomputed under the policy’s own
> harder boundary. Logs explained the failure after it happened. They gave
> nobody a reason to search for it before trusting the decision.
>
> Dissent turns an agent policy into a counterexample bounty. The agent commits
> to a deterministic rule and locks MON behind its boundary. A challenger seals
> and later reveals evidence. Monad runs the registered computation and pays
> only if the evidence breaks the committed rule. No LLM judge, vote or
> administrator decides the result.
>
> The working demonstration records the full flow on Monad: commitment, hidden
> challenge, reveal, deterministic recomputation and settlement. A separate
> fault path shows that a broken adapter does not receive the same treatment as
> a valid counterexample.
>
> Poker is the proof case, not the protocol. Dissent is for agent outputs where
> finding a bad state is difficult, checking it is deterministic, and the value
> protected is greater than the cost of the challenge. External adoption and an
> independent audit are still open work.

## Demonstrated limitations

- No independent team has integrated Dissent yet.
- No external audit has been completed.
- The first public domain adapter is poker-derived; broader applicability is an
  architectural claim supported by the interface, not demonstrated adoption.
- The recomputer defines domain meaning. Dissent guarantees challenge mechanics,
  not universal truth.
- A reclaimed claim is not a verified claim; it only means no successful
  challenge settled before closure.

## Submission assets still required

- Public repository: <https://github.com/alnitak34/dissent> (currently private)
- **[FINAL VIDEO URL]**
- Mainnet receipt set: `docs/MAINNET_LIVE_RUN.md`
- **[SCREENSHOTS / COVER IMAGE]**
- Final portal copy checked against the fields exposed when submissions open.

## Remaining blockers, in order

1. Record and upload the single public video of no more than 3 minutes.
2. Make the repository public before submission and keep it public as required
   by the rules.
3. Replace every remaining placeholder and perform a final factual and link
   audit before entering text in the portal.
