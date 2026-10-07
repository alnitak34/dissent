# Metropolis video script — Dissent

Status: **recording candidate** checked against the current local five-phase
landing on 3 October 2026. It has not been recorded, uploaded or submitted.

Target: one continuous public video at or below `3:00`. The planned finish is
`2:51`, leaving a small safety margin.

## The sentence a judge must remember

> An agent funds a measurable rule. A challenger gets paid for proving one
> permitted case where that committed rule breaks.

## Recording plan and exact spoken script

| Time | Screen and action | Spoken script |
| --- | --- | --- |
| 0:00–0:22 | Hero and recorded result | “Hi, I build as Alnitak. Agents increasingly publish numerical decisions that trigger actions. Dissent lets an operator fund a measurable rule, and rewards a challenger who proves one permitted case where that committed rule breaks.” |
| 0:22–0:43 | Phase 01 — `RULE COMMITTED`; show the boundary, recomputer and bounty, then click `Continue to sealed evidence` | “First, the agent commits to the rule, its numerical boundary, a specific deterministic recomputer and a bounty. Those terms cannot change after the challenge begins. Here, the allowed violation count is zero, and the agent locks three MON.” |
| 0:43–1:00 | Phase 02 — `EVIDENCE SEALED`; show deposit and hidden hash, then click `Open the reveal record` | “A challenger deposits point one MON and seals a hash of the evidence. The scenario stays hidden until the reveal window. This prevents the challenger from changing the case after seeing the response.” |
| 1:00–1:16 | Phase 03 — `EVIDENCE REVEALED`; show the permitted historical state, then click `Inspect the recomputed result` | “The challenger reveals a permitted historical state in the exact evidence format. This is not an argument with the agent. It is structured input for the recomputer fixed in phase one.” |
| 1:16–1:39 | Phase 04 — `RULE REFUTED`; show `1` against maximum `0`, then click `Follow the bounty` | “Monad executes that recomputer onchain. No language model, vote or administrator chooses the winner. In this hand, the recomputed violation is one. The committed maximum was zero, so this valid counterexample refutes the rule.” |
| 1:39–1:57 | Phase 05 — `BOUNTY SETTLED`; show the payout and click `Verify the record on Monad` | “Dissent credits the three MON bounty, returns the challenger’s point one MON deposit, and allows the complete three point one MON credit to be withdrawn.” |
| 1:57–2:17 | Wait for `VERIFIED ON MONAD MAINNET`; show receipts and final state | “The page now checks four receipts, the success event, the withdrawal and the final contract state directly on Monad Mainnet. The commitment is Challenged, and every phase links to its public transaction.” |
| 2:17–2:38 | `THE PROTOCOL, NOT THE POKER` | “The poker hand is the proof case, not the product. Dissent Core contains no card logic. Another domain can integrate only by defining and reviewing its own measurable rule, bounded evidence and deterministic recomputer.” |
| 2:38–2:51 | `WHY MONAD` and honest limits | “Monad provides the public execution path for recomputation and settlement. This case proves the mechanism ran; it does not prove an audit, adoption or universal truth. Agents make claims. Dissent funds the objection.” |

## Facts that must remain exact

- Network: Monad Mainnet, chain id `143`.
- Rule: violation count must be at most `0`.
- Recomputed result: `1`.
- Agent bounty: `3 MON`.
- Challenger deposit: `0.1 MON`.
- Challenger credit and withdrawal: `3.1 MON`.
- Public proof: four transaction receipts, `ChallengeSucceeded`, the challenger
  withdrawal and final commitment state `Challenged`.
- Recorded economics: the challenger received the bounty but finished
  `0.088395576 MON` below its starting balance after gas. Never describe the
  case as guaranteed profit.

The authoritative hashes, blocks, addresses and balance reconciliation are in
[`MAINNET_LIVE_RUN.md`](MAINNET_LIVE_RUN.md).

## Recording rules

- Record the working public website, not slides or a code walkthrough.
- Make every click before speaking about the state it reveals.
- Do not claim a successful live check until the page says
  `VERIFIED ON MONAD MAINNET`.
- If it ends at `NOT VERIFIED NOW`, show the recorded hashes and say that the
  live RPC check is unavailable at that moment. Do not pretend it succeeded.
- Do not show wallet popups, balances, notifications, private chats, salts,
  seed phrases or private keys.
- Manually correct captions for `Dissent`, `Monad`, `Alnitak`, `recomputer`
  and `counterexample`.
- Do not record the final take until this landing version is public and its
  complete route has passed the public preflight in the runbook.

## Honest boundary

- No independent operator has integrated Dissent yet.
- No external security audit has been completed.
- Willingness to pay and repeat demand have not been established.
- Applicability beyond poker is architectural; a second public domain flow has
  not been completed.
