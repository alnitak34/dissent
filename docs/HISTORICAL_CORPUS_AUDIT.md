# Historical corpus audit — Alnitak River Safety v1

Status: **local retrospective evidence, not out-of-sample validation**.

This audit answers one narrow question: can the policy-bounty tooling start
from raw arena.dev.fun replays, reconstruct eligible states without naming a
winner, and find more than the one demonstration fixture?

## Reproducible command

From the repository root:

```powershell
python bridge/exportar_policy_bounty.py <S17_REPLAYS> <S18_REPLAYS>
```

`bridge/exportar_policy_bounty.py` reads the raw replay events, identifies
Alnitak's heads-up river calls, reconstructs the observable aggressive trace,
and passes each eligible state to the independent Python verifier. It does not
use the showdown winner, the opponent's cards, or the chip result to classify
a violation.

## Measured local corpus

| Corpus | Raw replay files | Unreadable | Eligible states | Counterexamples |
| --- | ---: | ---: | ---: | ---: |
| S17 | 1,359 | 0 | 4 | 0 |
| S18 Playground | 825 | 0 | 7 | 3 |
| **Total** | **2,184** | **0** | **11** | **3** |

“Eligible” means all of the following were present and valid: an Alnitak river
call, a complete five-card board and two-card hand, exactly one active opponent
at the decision, positive pot and call amounts, and an aggressive trace inside
the policy's registered high-pressure domain.

## Counterexamples found

| Table / sequence | Hand and board | Old exact equity | Pressure-conditioned equity | Required threshold |
| --- | --- | ---: | ---: | ---: |
| `cmtqg8o677abb15he3gpl6qe1` / 26 | Qh Js / 7h 7s Qs Th 2c | 70.627803% | 30.157102% | 42.868852% |
| `cmtqx9zrvtjgw15hehpbf9gxk` / 30 | Ac 8c / Ks 7h 5d Qc 9h | 81.873479% | 7.928493% | 48.333333% |
| `cmtrmn8t8e6xvdjxw086hbaod` / 32 | Jh Jd / 5c 9s 2h 6h 4c | 56.894150% | 32.004567% | 42.417027% |

The three are different replays and different decisions. Their public action
traces end respectively in a river raise, a multi-street opponent bet, and a
river raise. The historical outcomes were inspected only after classification;
all three lost at showdown, but that fact is context and never enters the
verdict.

## What this proves

- The current exporter can derive policy candidates from raw replays rather
  than from the two hand-authored demo fixtures.
- The scanner finds three distinct historical violations without a hard-coded
  table id, hand, board, or expected winner.
- The known Jh/Jd fixture is reproducible from its raw source replay.

## What this does not prove

- It does not prove that the two local directories are the complete history of
  every Alnitak hand. The counts above are file counts in the inspected cache.
- It does not prove the policy generalizes. Only 11 of 2,184 replays fall inside
  this deliberately narrow domain.
- It is not clean out-of-sample evidence. The policy was designed after some of
  these failures, including the known Jh/Jd case, had already been inspected.
- No challenge against this policy adapter has yet been settled on Monad. The
  policy-bounty adapter remains a local prototype until separately reviewed,
  committed, deployed, and exercised end to end.

The stronger next validation is prospective: freeze the canonical policy hash,
then scan later replays that were not available during its design. That result
must be reported whether it finds zero or many counterexamples.
