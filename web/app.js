import { hasSuccessfulChallenge, hasWithdrawal } from "./proof.mjs";

const RPC_URL = "https://rpc.monad.xyz";
const EXPLORER = "https://monadvision.com";
const CORE = "0x9D673a8B5EfE76D42593b45972Fa0426648967E1";
const REGISTRY = "0x2a26e33CD2118a2D340bbA810e23a8E5CfdE8E38";
const RECOMPUTER = "0x6dCD184c9c0db42FCD0De731F9a2855b38916758";
const CHALLENGER = "0x00cf6ceC697E3DCB88a5972Ef083B423dfC00A02";
const COMMITMENT = "0xdd6e1e25ce02dd6cad370597156da960921d4eb671d50022ab0083f31391cccb";
const CHALLENGE_SUCCEEDED = "0x91c1883709a1e9edb879e595583d9d3b74a04df0fbaf5b3eb92587fadfc17e78";
const WITHDRAWN = "0x7084f5476618d8e60b11ef0d7d3f06914655adb8793e28ff7f018d4c76d505d5";
const PAYOUT = 3100000000000000000n;
const RPC_TIMEOUT_MS = 8000;

const transactions = [
  { name: "Commit", detail: "Agent locks 3 MON", hash: "0x59c55bd184635cae41d2f00a56b90b5f5da07e12edef60f2642d727f0c476dd0", block: 108439200 },
  { name: "Seal", detail: "Challenger locks 0.1 MON with hidden evidence", hash: "0x17e815f3f6ac6781e7981665ca741e92847a4a301771100dae15269b22321cf0", block: 108440776 },
  { name: "Reveal", detail: "Violation 1 exceeds threshold 0", hash: "0xbc121f84234ec22fc8aace845333e3b4e169c2f55776fa55f967d70317a4f529", block: 108441453 },
  { name: "Challenger withdraws", detail: "3.1 MON credit collected", hash: "0xf2378b1d2b3bb6420c0894c6d760576c35adb393bc71d0fce69852a4ddf8e336", block: 108442607 },
];

const phases = [
  {
    tx: 0,
    state: "RULE COMMITTED",
    block: "108,439,200",
    window: "Reveal window: not opened",
    kind: "TRANSACTION",
    title: "The agent commits the rule and locks 3.00 MON.",
    action: "Continue to sealed evidence",
  },
  {
    tx: 1,
    state: "EVIDENCE SEALED",
    block: "108,440,776",
    window: "Reveal window: pending",
    kind: "TRANSACTION",
    title: "The challenger seals the evidence and locks 0.10 MON.",
    action: "Open the reveal record",
  },
  {
    tx: 2,
    state: "EVIDENCE REVEALED",
    block: "108,441,453",
    window: "Reveal window: open at execution",
    kind: "TRANSACTION",
    title: "The permitted historical state is revealed to the recomputer.",
    action: "Inspect the recomputed result",
  },
  {
    tx: 2,
    state: "RULE REFUTED",
    block: "108,441,453",
    window: "Reveal window: settlement recorded",
    kind: "EVENT · CHALLENGESUCCEEDED",
    title: "The same reveal receipt records violation 1 above maximum 0.",
    action: "Follow the bounty",
  },
  {
    tx: 3,
    state: "BOUNTY SETTLED",
    block: "108,442,607",
    window: "Reveal window: closed",
    kind: "TRANSACTION",
    title: "The challenger withdraws the full 3.10 MON credit.",
    action: "Verify the record on Monad",
  },
];

const selectors = {
  commitment: `0x7795820c${COMMITMENT.slice(2)}`,
};

let requestId = 0;
let replayStage = 0;

async function rpc(method, params) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), RPC_TIMEOUT_MS);
  try {
    const response = await fetch(RPC_URL, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ jsonrpc: "2.0", id: ++requestId, method, params }),
      signal: controller.signal,
    });
    if (!response.ok) throw new Error(`RPC HTTP ${response.status}`);
    const payload = await response.json();
    if (payload.error) throw new Error(payload.error.message || "RPC error");
    return payload.result;
  } catch (error) {
    if (error.name === "AbortError") {
      throw new Error("Monad RPC did not respond within 8 seconds.");
    }
    throw error;
  } finally {
    clearTimeout(timeout);
  }
}

function shortHash(value) {
  return `${value.slice(0, 8)}…${value.slice(-6)}`;
}

function renderTimeline(receipts = [], verification = "recorded") {
  const timeline = document.querySelector("#timeline");
  timeline.innerHTML = transactions.map((tx, index) => {
    const receipt = receipts[index];
    const confirmed = receipt?.status === "0x1" && Number.parseInt(receipt.blockNumber, 16) === tx.block;
    const verificationState = confirmed ? "verified" : verification;
    const verificationCopy = verificationState === "verified"
      ? "Verified now"
      : verificationState === "checking"
        ? "Verifying…"
        : verificationState === "unverified"
          ? "Not verified now"
          : "Recorded case";
    return `
      <article class="tx-step ${confirmed ? "ok" : verificationState}">
        <div class="tx-top"><span class="number">0${index + 1}</span><span class="status"></span></div>
        <h3>${tx.name}</h3>
        <p>${tx.detail}<br />Block ${tx.block.toLocaleString("en-US")}</p>
        <span class="tx-verification">${verificationCopy}</span>
        <a href="${EXPLORER}/tx/${tx.hash}" target="_blank" rel="noreferrer">${shortHash(tx.hash)} ↗</a>
      </article>`;
  }).join("");
}

function lastWord(hex) {
  return hex.slice(-64);
}

async function withinDeadline(promise, timeoutMs) {
  let timeout;
  try {
    return await Promise.race([
      promise,
      new Promise((_, reject) => {
        timeout = setTimeout(() => reject(new Error("Monad RPC did not respond within 8 seconds.")), timeoutMs);
      }),
    ]);
  } finally {
    clearTimeout(timeout);
  }
}

async function readProof() {
  const refresh = document.querySelector("#refresh");
  const verdict = document.querySelector("#verdict");
  refresh.disabled = true;
  verdict.dataset.state = "loading";
  verdict.querySelector(".verdict-icon").textContent = "···";
  verdict.querySelector(".label").textContent = "Reading Monad Mainnet";
  verdict.querySelector("h3").textContent = "Checking the proof directly from the chain";
  document.querySelector("#verdict-detail").textContent = "Four receipts, the ChallengeSucceeded event, the challenger withdrawal and the final contract state are being checked.";
  renderTimeline([], "checking");

  try {
    const [receipts, commitmentData] = await withinDeadline(Promise.all([
      Promise.all(transactions.map((tx) => rpc("eth_getTransactionReceipt", [tx.hash]))),
      rpc("eth_call", [{ to: CORE, data: selectors.commitment }, "latest"]),
    ]), RPC_TIMEOUT_MS);

    renderTimeline(receipts);
    const allConfirmed = receipts.every((receipt, index) =>
      receipt?.status === "0x1" && Number.parseInt(receipt.blockNumber, 16) === transactions[index].block &&
      receipt.to?.toLowerCase() === CORE.toLowerCase());
    const status = Number.parseInt(lastWord(commitmentData), 16);
    const challengeConfirmed = hasSuccessfulChallenge(receipts[2], {
      core: CORE,
      eventTopic: CHALLENGE_SUCCEEDED,
      commitment: COMMITMENT,
      challenger: CHALLENGER,
      newValue: 1n,
      threshold: 0n,
      payout: PAYOUT,
    });
    const challengerWithdrew = hasWithdrawal(receipts[3], {
      core: CORE,
      eventTopic: WITHDRAWN,
      beneficiary: CHALLENGER,
      amount: PAYOUT,
    });
    const complete = allConfirmed && challengeConfirmed && challengerWithdrew && status === 2;

    if (!complete) {
      throw new Error("The current state does not match the recorded completed challenge.");
    }

    verdict.dataset.state = "success";
    verdict.querySelector(".verdict-icon").textContent = "✓";
    verdict.querySelector(".label").textContent = "Verified on Monad Mainnet";
    verdict.querySelector("h3").textContent = "The recorded proof matches the chain";
    document.querySelector("#verdict-detail").textContent = "The four receipts, the ChallengeSucceeded event, the challenger withdrawal and the final Challenged contract state were verified.";
  } catch (error) {
    verdict.dataset.state = "unverified";
    verdict.querySelector(".verdict-icon").textContent = "?";
    verdict.querySelector(".label").textContent = "Not verified now";
    verdict.querySelector("h3").textContent = "Live verification is unavailable right now";
    document.querySelector("#verdict-detail").textContent = "The case remains recorded on Monad Mainnet. Its transaction hashes, block numbers and contract addresses are listed below; use the existing MonadVision links to verify them directly.";
    renderTimeline([], "unverified");
  } finally {
    refresh.disabled = false;
  }
}

function updatePhaseRecord(stage) {
  const phase = phases[stage];
  const tx = transactions[phase.tx];
  document.querySelector("#instrument-state").textContent = phase.state;
  document.querySelector("#instrument-count").textContent = `0${stage + 1} / 05`;
  document.querySelector("#instrument-block").textContent = phase.block;
  document.querySelector("#instrument-window").textContent = phase.window;
  document.querySelector("#phase-kind").textContent = phase.kind;
  document.querySelector("#phase-title").textContent = phase.title;
  document.querySelector("#phase-hash").textContent = shortHash(tx.hash);
  document.querySelector("#phase-link").href = `${EXPLORER}/tx/${tx.hash}`;
  document.querySelector("#phase-panel").setAttribute("aria-labelledby", `phase-${stage}`);
  document.querySelectorAll(".instrument-track i").forEach((segment, index) => {
    segment.classList.toggle("filled", index <= stage);
  });
  document.querySelectorAll("[data-phase]").forEach((button, index) => {
    const active = index === stage;
    button.classList.toggle("active", active);
    button.classList.toggle("complete", index < stage);
    button.setAttribute("aria-selected", active ? "true" : "false");
    button.tabIndex = active ? 0 : -1;
  });
}

function setReplayStage(stage) {
  replayStage = Math.max(0, Math.min(phases.length - 1, Number(stage)));
  const replay = document.querySelector("#replay");
  const rail = document.querySelector("#payout-rail");
  const action = document.querySelector("#replay-action");
  const summary = document.querySelector(".replay-summary");
  const proofResult = document.querySelector("#proof-result");
  replay.dataset.phase = String(replayStage);
  rail.dataset.phase = String(replayStage);
  proofResult.hidden = replayStage !== 4;
  updatePhaseRecord(replayStage);
  action.textContent = phases[replayStage].action;

  if (replayStage === 0) {
    document.querySelector("#versus-copy").textContent = "rule recorded";
    document.querySelector("#challenger-label").textContent = "Counterexample status";
    document.querySelector("#stage-value").textContent = "OPEN";
    document.querySelector("#stage-comparison").textContent = "No evidence seal has been recorded yet";
    document.querySelector("#challenge-result").textContent = "Waiting";
    document.querySelector("#agent-result").textContent = "Rule holds";
    document.querySelector("#agent-funds").textContent = "3.00 MON locked";
    document.querySelector("#challenger-funds").textContent = "No deposit yet";
    document.querySelector("#replay-copy").textContent = "The rule is bound to the recomputer and the 3.00 MON bounty is funded.";
    summary.hidden = true;
  } else if (replayStage === 1) {
    document.querySelector("#versus-copy").textContent = "evidence sealed";
    document.querySelector("#challenger-label").textContent = "Hidden counterexample";
    document.querySelector("#stage-value").textContent = "SEALED";
    document.querySelector("#stage-comparison").textContent = "Only the evidence hash is public";
    document.querySelector("#challenge-result").textContent = "Reveal pending";
    document.querySelector("#agent-result").textContent = "Rule holds";
    document.querySelector("#agent-funds").textContent = "3.00 MON locked";
    document.querySelector("#challenger-funds").textContent = "0.10 MON deposit locked";
    document.querySelector("#replay-copy").textContent = "The challenger commits the evidence hash without exposing the scenario before the reveal window.";
    summary.hidden = true;
  } else if (replayStage === 2) {
    document.querySelector("#versus-copy").textContent = "scenario revealed";
    document.querySelector("#challenger-label").textContent = "Permitted scenario";
    document.querySelector("#stage-value").textContent = "Jh Jd";
    document.querySelector("#stage-comparison").textContent = "River: 5c 9s 2h 6h 4c · pressure trace included";
    document.querySelector("#challenge-result").textContent = "Ready to recompute";
    document.querySelector("#agent-result").textContent = "Rule holds";
    document.querySelector("#agent-funds").textContent = "3.00 MON locked";
    document.querySelector("#challenger-funds").textContent = "0.10 MON deposit locked";
    document.querySelector("#replay-copy").textContent = "The historical state is revealed. The registered recomputer now evaluates the same committed rule.";
    summary.hidden = true;
  } else if (replayStage === 3) {
    document.querySelector("#versus-copy").textContent = "recomputed onchain";
    document.querySelector("#challenger-label").textContent = "Deterministic result";
    document.querySelector("#stage-value").textContent = "1";
    document.querySelector("#stage-comparison").innerHTML = "violation <strong>1 &gt; allowed maximum 0</strong>";
    document.querySelector("#challenge-result").textContent = "Rule refuted";
    document.querySelector("#agent-result").textContent = "Original rule refuted";
    document.querySelector("#agent-funds").textContent = "0 bounty returned";
    document.querySelector("#challenger-funds").textContent = "3.10 MON credited";
    document.querySelector("#replay-copy").textContent = "The recomputer returns 1. The contract records the threshold breach and credits the bounty plus the deposit.";
    summary.hidden = false;
  } else {
    document.querySelector("#versus-copy").textContent = "settled onchain";
    document.querySelector("#challenger-label").textContent = "Withdrawal complete";
    document.querySelector("#stage-value").textContent = "3.10 MON";
    document.querySelector("#stage-comparison").textContent = "3.00 bounty + 0.10 deposit returned";
    document.querySelector("#challenge-result").textContent = "Paid and withdrawn";
    document.querySelector("#agent-result").textContent = "Rule refuted";
    document.querySelector("#agent-funds").textContent = "0 bounty returned";
    document.querySelector("#challenger-funds").textContent = "3.10 MON withdrawn";
    document.querySelector("#replay-copy").textContent = "The withdrawal receipt closes the recorded case. Inspect all four transactions and the current state below.";
    summary.hidden = false;
    readProof();
  }
}

function advanceReplay() {
  if (replayStage < phases.length - 1) {
    setReplayStage(replayStage + 1);
  } else {
    document.querySelector("#verdict").scrollIntoView({ behavior: "smooth", block: "center" });
    readProof();
  }
}

document.querySelector("#commitment-id").textContent = COMMITMENT;
document.querySelector("#core-address").textContent = CORE;
document.querySelector("#registry-address").textContent = REGISTRY;
document.querySelector("#recomputer-address").textContent = RECOMPUTER;
document.querySelector("#core-link").href = `${EXPLORER}/address/${CORE}`;
document.querySelector("#registry-link").href = `${EXPLORER}/address/${REGISTRY}`;
document.querySelector("#recomputer-link").href = `${EXPLORER}/address/${RECOMPUTER}`;
document.querySelector("#decisive-receipt").href = `${EXPLORER}/tx/${transactions[2].hash}`;
document.querySelector("#refresh").addEventListener("click", readProof);
document.querySelector("#replay-action").addEventListener("click", advanceReplay);
document.querySelector("#reset-replay").addEventListener("click", () => setReplayStage(0));
document.querySelectorAll("[data-start-replay]").forEach((link) => {
  link.addEventListener("click", () => setReplayStage(0));
});
document.querySelectorAll("[data-phase]").forEach((button) => {
  button.addEventListener("click", () => setReplayStage(button.dataset.phase));
  button.addEventListener("keydown", (event) => {
    const current = Number(button.dataset.phase);
    if (!["ArrowLeft", "ArrowRight", "Home", "End"].includes(event.key)) return;
    event.preventDefault();
    const next = event.key === "Home" ? 0 : event.key === "End" ? 4 : event.key === "ArrowLeft" ? Math.max(0, current - 1) : Math.min(4, current + 1);
    setReplayStage(next);
    document.querySelector(`[data-phase="${next}"]`).focus();
  });
});

document.querySelectorAll(".copy-value").forEach((button) => {
  button.addEventListener("click", async () => {
    const value = document.querySelector(`#${button.dataset.copyTarget}`).textContent;
    try {
      await navigator.clipboard.writeText(value);
      button.textContent = "Copied";
      setTimeout(() => { button.textContent = "Copy"; }, 1200);
    } catch {
      button.textContent = "Select value";
    }
  });
});

const equityControl = document.querySelector("#equity-control");
function updateBoundaryExplorer() {
  const equity = Number(equityControl.value);
  const breaksRule = equity < 42.417027417027417;
  document.querySelector("#equity-output").textContent = `${equity.toFixed(2)}%`;
  const verdict = document.querySelector("#lab-verdict");
  verdict.dataset.result = breaksRule ? "1" : "0";
  verdict.querySelector("strong").textContent = breaksRule ? "1 · RULE BREAKS" : "0 · RULE HOLDS";
}
equityControl.addEventListener("input", updateBoundaryExplorer);

document.querySelector('a[href="#contracts"]').addEventListener("click", () => setReplayStage(4));
renderTimeline();
setReplayStage(0);
updateBoundaryExplorer();
