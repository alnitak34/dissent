# Metropolis recording runbook — Dissent

Status: **public preflight candidate**. It reflects the current five-phase
landing and the completed Monad Mainnet case. The public Vercel landing was
visually checked against this structure on 7 October 2026; the complete route
must still pass the preflight below immediately before the final recording.

## Sources of truth

1. [`MAINNET_LIVE_RUN.md`](MAINNET_LIVE_RUN.md) is authoritative for network,
   addresses, hashes, blocks, balances and final state.
2. [`VIDEO_SCRIPT_DRAFT.md`](VIDEO_SCRIPT_DRAFT.md) is the exact narration.
3. [`VIDEO_REHEARSAL.md`](VIDEO_REHEARSAL.md) controls pronunciation and pauses.
4. The final public website controls what can actually be shown.

If these disagree, stop. Correct the discrepancy before recording.

## Truth boundary

Safe claims:

- The demonstrated five-phase case completed on Monad Mainnet.
- Four public transactions record commit, seal, reveal and withdrawal.
- The recomputer returned violation `1` against committed maximum `0`.
- The contract credited a `3 MON` bounty and returned a `0.1 MON` deposit; the
  challenger withdrew `3.1 MON`.
- The poker adapter is one proof case. `DissentCore` contains no card logic.

Required limitations:

- Source verification is not an external audit.
- No independent operator integration is claimed.
- Demand, pricing and repeated use are not established.
- The demonstrated challenger was not profitable after gas.
- One successful case does not prove every recomputer or future domain safe.

## Public preflight before the final take

1. Open the deployed Vercel URL in a private browser window.
2. Confirm the hero defines Dissent and states the recorded result without a
   click.
3. Confirm navigation to `case`, `protocol`, `contracts` and `docs`.
4. Reset the dossier and traverse all five phases using the exact button labels
   in the rehearsal script.
5. Confirm the visible values are `0`, `1`, `3 MON`, `0.1 MON` and `3.1 MON`.
6. Confirm each phase opens the correct Mainnet explorer transaction.
7. Run `Verify the record on Monad`. It must resolve to either
   `VERIFIED ON MONAD MAINNET` or `NOT VERIFIED NOW`; it must never remain in a
   permanent checking state.
8. Open the complete transaction list, core address and recomputer address.
   Confirm copy buttons and explorer links.
9. Open protocol and integration documentation from the public site.
10. Repeat the critical route on mobile and desktop widths.
11. Close wallets, notifications, private chats, balances and unrelated tabs.

Do not record a final take while the public website still shows the older
three-stage replay.

## Capture settings

- One continuous take, `1080p`, maximum `3:00`.
- Use a clean browser profile or private window.
- Set zoom before recording; do not change it during the take.
- Keep the pointer still unless it indicates the next action.
- Do not accelerate the video in a way that makes receipts unreadable.
- Correct captions manually after export.

## Screen-action checklist

| Order | Required visible state | Action |
| --- | --- | --- |
| 1 | Hero and recorded result | Define the product and case outcome. |
| 2 | `01 RULE COMMITTED` | Show rule, boundary, recomputer and bounty; continue. |
| 3 | `02 EVIDENCE SEALED` | Show deposit and evidence hash; open reveal. |
| 4 | `03 EVIDENCE REVEALED` | Show permitted historical state; inspect result. |
| 5 | `04 RULE REFUTED` | Show `1` against maximum `0`; follow bounty. |
| 6 | `05 BOUNTY SETTLED` | Show `3.1 MON`; start verification. |
| 7 | Final Mainnet verification state | Show four receipts and `Challenged`. |
| 8 | `THE PROTOCOL, NOT THE POKER` | Explain reuse beyond the first adapter. |
| 9 | `WHY MONAD` and limitations | Close on the precise claim and Dissent name. |

## Failure branches

- **RPC unavailable:** use the explicit `NOT VERIFIED NOW` line from the
  rehearsal and show explorer links. Never call it a live success.
- **Wrong network, hash or block:** stop recording and correct the page.
- **Layout or performance failure:** stop; remove the expensive effect or fix
  the route before attempting another take.
- **Narration and screen disagree:** the screen and chain evidence win.

## Review before upload or submission

- Duration is at or below `3:00`.
- Audio is understandable without captions.
- Captions spell `Dissent`, `Monad`, `Alnitak`, `recomputer` and
  `counterexample` correctly.
- No secret, wallet balance, notification or private conversation is visible.
- Mainnet is never confused with the earlier Testnet work.
- The video URL opens without login in a private browser.
- The submission text does not claim audit, adoption, guaranteed profit or
  validation beyond the demonstrated mechanism.
