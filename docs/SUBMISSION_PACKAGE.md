# Metropolis submission package — Dissent

Status snapshot: **20 September 2026**. This file is an execution checklist,
not a claim that the project has already been submitted.

Official track: [Trust, Identity & AI Infrastructure](https://hackathon.monad.xyz/tracks/trust-identity-ai).
Deadline shown by the portal: **14 October 2026, 05:59 GMT+2**.
The submission window shown by the portal opens **22 September 2026**.

## Positioning

**Project name:** Dissent

**One-line description:**

> Agents stake MON behind falsifiable numerical claims, and anyone who proves
> them wrong gets paid onchain.

**Full description proposed for the project page:**

> Dissent is a counterexample-bounty protocol for autonomous agent policies.
> An agent commits to a deterministic numerical boundary and escrows MON.
> Challengers seal and reveal valid states; a versioned onchain recomputer
> evaluates the agreed rule, and Monad settles the bounty only when a canonical
> value crosses the threshold. The live testnet case uses Alnitak's poker agent:
> one historical state broke its river policy, the hardened core paid the
> challenger, and a separate faulty-adapter run returned funds without paying a
> bounty. Poker is the first adapter, not the protocol: every new domain needs
> its own deterministic, reviewed recomputer. External audit, independent
> integrations and proof of demand remain pending.

**Repository URL to enter:** <https://github.com/alnitak34/dissent>

## Deliverable audit

| Official deliverable | Current evidence | Status / next action |
|---|---|---|
| Project logo, max 3 MB | `web/assets/dissent-mark-1024.png` — 29,927 bytes | Ready |
| Public GitHub repository | `https://github.com/alnitak34/dissent` | **Blocked while private.** Make public only when the release review is complete. |
| Technical demo, max 3 minutes | No YouTube, Loom or Vimeo URL in the repo | Record and upload |
| Pitch video, max 2 minutes | No YouTube, Loom or Vimeo URL in the repo | Record and upload |
| Live product link | `https://dissent-henna.vercel.app/` | Ready; perform a final mobile and desktop check before submission |
| Optional 30-second advertisement | None | Optional; do not prioritize before required videos |

## Evidence to show, not merely claim

- Hardened `DissentCore` on Monad Testnet:
  `0x460f9F624da9e23c705c610E1263bf3641bCce23`.
- Policy recomputer on Monad Testnet:
  `0x10EE57C2c75308118C527d909c6FDCF77BBaCb2d`.
- Completed valid challenge and withdrawals:
  `docs/POLICY_BOUNTY_LIVE_RUN.md`.
- Non-payable technical fault executed onchain:
  `docs/FAULT_PROBE.md`.
- Public replay reads the seven Policy Bounty receipts and final state from the
  public Monad Testnet RPC.
- Security validation passed on `master` after PR #1. This is CI evidence, not
  an external audit.

## Technical demo — maximum 3 minutes

Do not show slides or walk through code. Record the live product.

1. **0:00–0:20 — Problem.** Open the landing page. Say: “Agents test the cases
   they expect. Dissent funds the search for the state they missed.”
2. **0:20–0:45 — Agreed rule.** Show the Alnitak claim, threshold and 3 test MON
   warranty. State that the recomputer and rule were bound before the evidence.
3. **0:45–1:25 — Reveal.** Run the replay. Reveal the historical hand and show
   the deterministic recomputation crossing the agreed threshold.
4. **1:25–1:55 — Settlement.** Show `POLICY BROKEN`, the challenger payout and
   the final zero balances after both withdrawals.
5. **1:55–2:25 — Verify.** Open the receipt links and the verified Testnet
   contracts. State clearly that source verification is not an audit.
6. **2:25–2:45 — Failure safety.** Explain that an adapter revert does not pay a
   bounty: the deposit returns to the challenger and the reward to the agent.
7. **2:45–3:00 — Generality and boundary.** Poker is the first adapter. Other
   agents need their own deterministic, reviewed recomputer; demand and external
   integrations are not yet proven.

## Pitch video — maximum 2 minutes

Draft spoken script:

> Hi, I'm Julieth, and I build under the name Alnitak. For months I watched my
> poker agent make decisions that looked justified but failed in states its
> policy had not modeled. Logs explained the failure afterwards. They gave
> nobody a reason to search for it beforehand.
>
> Dissent turns an agent policy into a counterexample bounty. The agent commits
> to a numerical boundary and deterministic recomputer, then locks MON behind
> the claim. A challenger seals and reveals evidence. Monad runs the agreed
> computation and pays if the value crosses the boundary. No LLM judge, vote or
> admin decides the result.
>
> In the live Testnet case, one historical Alnitak state broke its river policy,
> and Dissent settled the bounty onchain. The site verifies the receipts and
> final state. After mentor feedback, I changed the protocol so a technical
> adapter failure never pays a bounty, then executed that path separately on
> Monad Testnet.
>
> Poker is the proof case, not the whole product. Dissent is for agents whose
> numerical outputs control meaningful value and whose counterexamples can be
> checked deterministically. Each domain still needs a reviewed recomputer.
> External demand and an independent audit remain unproven. My next step is one
> real integration beyond my own agent.

## Remaining blockers, in order

1. Complete the project-page description and repository URL.
2. Obtain one independent technical review or integration signal. A reply is
   evidence of interest; only code used by another team is an integration.
3. Record the live technical demo.
4. Record the founder/problem pitch.
5. Run the final release review, then make the repository public for submission.
6. Enter the URLs after the submission window opens and submit only after a
   final truth audit.
