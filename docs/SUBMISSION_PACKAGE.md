# Metropolis submission package — Dissent

Status: **draft only**. Nothing in this file has been submitted to the
Metropolis portal. Replace every bracketed placeholder before publication.

## Project name

Dissent

## One-line description

Dissent lets agents fund measurable rules in MON and pays a challenger when a
registered deterministic recomputer verifies a permitted counterexample
onchain.

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

## Go-to-market and user acquisition — draft

The first users are builders of autonomous agents whose outputs can be reduced
to a measurable boundary and checked by a deterministic program. Dissent does
not target open-ended judgments or every agent workflow.

The initial acquisition path is integration-led rather than consumer-led:

1. Publish the core contracts, interface and one complete Mainnet reference
   adapter with reproducible receipts.
2. Work directly with a small number of agent builders to decide whether one of
   their existing numerical rules is bounded, valuable and cheap enough to
   verify onchain.
3. Build each new recomputer with the domain owner, publish its exact evidence
   format and test it against the owner's reference implementation before any
   value is attached.
4. Use completed, inspectable challenge records as integration evidence in
   Monad developer channels and direct technical outreach.

This is a proposed route, not established demand. No independent team has
integrated Dissent yet, and bounty pricing still needs validation against the
value protected and the cost of finding and proving a counterexample.

## Working product and evidence

- Public demo: <https://dissent-henna.vercel.app/>
- Repository: <https://github.com/alnitak34/dissent> — anonymous access returned
  `404` on 7 October 2026. The portal permits either a public repository or one
  shared with `metropolis@hackathon.monad.xyz`; verify the chosen access path
  before submission.
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
| Project identity | `Dissent`; 1024×1024 PNG logo at `web/assets/dissent-mark-1024.png` | Meets the portal's size and dimension limits |
| One-line description | Draft above | Fits the portal's 200-character limit |
| Long description | Draft above | Ready for final language review |
| Go-to-market | Draft above | Honest plan; no adoption claim |
| Live product | <https://dissent-henna.vercel.app/> | Working Mainnet replay; run the final mobile/desktop factual audit before capture |
| Code link | <https://github.com/alnitak34/dissent> | Make public or share with the organizer address, then verify access |
| Technical demo | 1080p candidate with audio: 2:46; no public URL recorded | Under the 3-minute limit |
| Pitch video | 1080p candidate with audio: 1:24; no public URL recorded | Under the 2-minute limit |
| Optional advertisement | 1080p candidate with audio: 0:24; no public URL recorded | Under the 30-second limit; does not affect judging |
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

## Completed Mainnet decision record

The Mainnet route has already been completed. The checklist below records the
gate that controlled that broadcast; it is retained as provenance, not as
pending work:

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

## Technical demo video — maximum 3 minutes

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

> Hi, I build under the name Alnitak. While operating my poker
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

## Pitch video — maximum 2 minutes

Use the rendered pitch to introduce Alnitak, the problem, the mechanism and the
reason for building Dissent. Keep the financial example visibly labelled as an
unbuilt illustration. Do not substitute this film for the technical demo: the
portal requires both fields separately.

## Judge access instructions — draft

No wallet or login is required. Open the live product and use the five phase
tabs, or the primary action button, to replay case D-001 from rule commitment to
bounty settlement. Each phase links to its Monad Mainnet receipt. At the end,
expand the transaction record and use “Refresh chain state” to retry the direct
RPC check if needed. The browser boundary explorer is explicitly illustrative;
the recorded settlement was computed by the deployed recomputer.

## Demonstrated limitations

- No independent team has integrated Dissent yet.
- No external audit has been completed.
- The first public domain adapter is poker-derived; broader applicability is an
  architectural claim supported by the interface, not demonstrated adoption.
- The recomputer defines domain meaning. Dissent enforces the implemented
  challenge mechanics under their assumptions, not universal truth.
- A reclaimed claim is not a verified claim; it only means no successful
  challenge settled before closure.

## Submission assets still required

- Repository access: make <https://github.com/alnitak34/dissent> public or share
  it with `metropolis@hackathon.monad.xyz`, then test the chosen access path.
- **[TECHNICAL DEMO VIDEO URL]**
- **[PITCH VIDEO URL]**
- **[OPTIONAL PROMOTIONAL VIDEO URL]**
- Mainnet receipt set: `docs/MAINNET_LIVE_RUN.md`
- Project logo: `web/assets/dissent-mark-1024.png`
- Final portal copy checked against the fields exposed when submissions open.

## Remaining blockers, in order

1. Review both local video candidates completely, including audio, privacy and
   correspondence with the current landing.
2. Upload the technical demo and pitch separately and test both URLs without a
   session. The promotional clip is optional.
3. Make the repository public or share it with the organizer address, then
   verify access from outside the owner session.
4. Upload the project logo and enter the prepared description, go-to-market,
   repository, product and video fields.
5. Replace every remaining placeholder and perform a final factual and link
   audit before reviewing or submitting the entry.

## Portal facts observed on 7 October 2026

- Submission deadline shown for Europe/Brussels: `14 October 2026, 05:59 GMT+2`.
- Required: logo, name, one-line description, long description, go-to-market,
  GitHub repository, live product, technical demo and pitch video.
- Repository instruction: public, or shared with
  `metropolis@hackathon.monad.xyz`.
- Technical demo: working product rather than slides or a code walkthrough, up
  to 3 minutes.
- Pitch video: team, problem and motivation, up to 2 minutes.
- Optional product advertisement: up to 30 seconds and explicitly stated not to
  affect judging.
