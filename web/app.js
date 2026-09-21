import { hasSuccessfulChallenge, hasWithdrawal } from "./proof.mjs";

const RPC_URL = "https://testnet-rpc.monad.xyz";
const EXPLORER = "https://testnet.monadvision.com";
const CORE = "0x686164f708b87d1A63bEE8Aa3130298246690a87";
const REGISTRY = "0xD92a8aa9C28168484abB6D03eC261DD1FC1b0B9b";
const RECOMPUTER = "0xaC87125846C19A978B3D847a9E49Dd7744aa6880";
const CHALLENGER = "0x00cf6ceC697E3DCB88a5972Ef083B423dfC00A02";
const COMMITMENT = "0x84f00753bfca460938625e9e0c84d0f856065ac9722f5ac3146ac7e71342389d";
const CHALLENGE_SUCCEEDED = "0x91c1883709a1e9edb879e595583d9d3b74a04df0fbaf5b3eb92587fadfc17e78";
const WITHDRAWN = "0x7084f5476618d8e60b11ef0d7d3f06914655adb8793e28ff7f018d4c76d505d5";
const PAYOUT = 3100000000000000000n;

const transactions = [
  { name: "Commit", detail: "Agent locks 3 test MON", hash: "0xccb717d253b65ac2ee77b892151dce3742408267fcc789fcf083b3e051220695", block: 64489596 },
  { name: "Seal", detail: "Challenger locks 0.1 test MON with hidden evidence", hash: "0x61fc21a587b7b0f0cdf7012ac033084f724766ff1a9b490c51454bfcaf2bd898", block: 64490792 },
  { name: "Reveal", detail: "Violation 1 exceeds threshold 0", hash: "0xa24eb7ed7aa64cf02bc6427db0b797216524098323a407b85d343436e0519c9a", block: 64494728 },
  { name: "Challenger withdraws", detail: "3.1 test MON credit collected", hash: "0x8fd736181047468ec05ff92522c5ecd143d3b0016b4b5d7c9545841d3044010d", block: 64496394 },
];

const selectors = {
  commitment: `0x7795820c${COMMITMENT.slice(2)}`,
};

let requestId = 0;
let replayStage = "claim";

async function rpc(method, params) {
  const response = await fetch(RPC_URL, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: ++requestId, method, params }),
  });
  if (!response.ok) throw new Error(`RPC HTTP ${response.status}`);
  const payload = await response.json();
  if (payload.error) throw new Error(payload.error.message || "RPC error");
  return payload.result;
}

function shortHash(value) {
  return `${value.slice(0, 8)}…${value.slice(-6)}`;
}

function renderTimeline(receipts = []) {
  const timeline = document.querySelector("#timeline");
  timeline.innerHTML = transactions.map((tx, index) => {
    const receipt = receipts[index];
    const confirmed = receipt?.status === "0x1" && Number.parseInt(receipt.blockNumber, 16) === tx.block;
    const block = confirmed ? Number.parseInt(receipt.blockNumber, 16).toLocaleString("en-US") : "Checking…";
    return `
      <article class="tx-step ${confirmed ? "ok" : ""}">
        <div class="tx-top"><span class="number">0${index + 1}</span><span class="status"></span></div>
        <h3>${tx.name}</h3>
        <p>${tx.detail}<br />Block ${block}</p>
        <a href="${EXPLORER}/tx/${tx.hash}" target="_blank" rel="noreferrer">${shortHash(tx.hash)} ↗</a>
      </article>`;
  }).join("");
}

function lastWord(hex) {
  return hex.slice(-64);
}

async function readProof() {
  const refresh = document.querySelector("#refresh");
  const verdict = document.querySelector("#verdict");
  refresh.disabled = true;
  verdict.dataset.state = "loading";
  verdict.querySelector(".verdict-icon").textContent = "···";
  verdict.querySelector(".label").textContent = "Reading Monad Testnet";
  verdict.querySelector("h3").textContent = "Checking the proof directly from the chain";
  document.querySelector("#verdict-detail").textContent = "Four receipts, the ChallengeSucceeded event, the challenger withdrawal and the commitment state are being checked.";

  try {
    const [receipts, commitmentData] = await Promise.all([
      Promise.all(transactions.map((tx) => rpc("eth_getTransactionReceipt", [tx.hash]))),
      rpc("eth_call", [{ to: CORE, data: selectors.commitment }, "latest"]),
    ]);

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
    verdict.querySelector(".label").textContent = "Live onchain state";
    verdict.querySelector("h3").textContent = "Claim refuted · payout withdrawn";
    document.querySelector("#verdict-detail").textContent = "Four receipts, the 1 > 0 payout event and the 3.1 test MON withdrawal confirmed. Commitment status: Challenged.";
  } catch (error) {
    verdict.dataset.state = "error";
    verdict.querySelector(".verdict-icon").textContent = "!";
    verdict.querySelector(".label").textContent = "Verification incomplete";
    verdict.querySelector("h3").textContent = "The live state could not be confirmed";
    document.querySelector("#verdict-detail").textContent = `${error.message} Open the transaction details below to inspect the receipts.`;
    renderTimeline();
  } finally {
    refresh.disabled = false;
  }
}

function setReplayStage(stage) {
  replayStage = stage;
  const replay = document.querySelector("#replay");
  const rail = document.querySelector("#payout-rail");
  const action = document.querySelector("#replay-action");
  const summary = document.querySelector(".replay-summary");
  const proofResult = document.querySelector("#proof-result");
  replay.dataset.stage = stage;
  rail.dataset.stage = stage;
  proofResult.hidden = stage !== "resolved";

  if (stage === "claim") {
    document.querySelector("#versus-copy").textContent = "scenario sealed";
    document.querySelector("#challenger-label").textContent = "Evidence seal · hidden scenario";
    document.querySelector("#stage-value").textContent = "SEALED";
    document.querySelector("#stage-comparison").textContent = "Hidden until the reveal window";
    document.querySelector("#challenge-result").textContent = "Waiting";
    document.querySelector("#agent-result").textContent = "Claim stands";
    document.querySelector("#agent-funds").textContent = "3.00 MON locked";
    document.querySelector("#challenger-funds").textContent = "0.10 MON deposit";
    document.querySelector("#replay-copy").textContent = "The challenger commits a hash of the evidence and locks a deposit. The scenario remains hidden until reveal.";
    action.textContent = "Reveal the scenario";
    summary.hidden = true;
  } else if (stage === "evidence") {
    document.querySelector("#versus-copy").textContent = "scenario revealed";
    document.querySelector("#challenger-label").textContent = "Permitted scenario";
    document.querySelector("#stage-value").textContent = "Jh Jd";
    document.querySelector("#stage-comparison").textContent = "River: 5c 9s 2h 6h 4c · pressure trace included";
    document.querySelector("#challenge-result").textContent = "Ready to recompute";
    document.querySelector("#agent-result").textContent = "Claim stands";
    document.querySelector("#replay-copy").textContent = "The historical state is revealed. Next, inspect the recomputation already recorded on Monad.";
    action.textContent = "Show the onchain verdict";
    summary.hidden = true;
  } else {
    document.querySelector("#versus-copy").textContent = "recomputed onchain";
    document.querySelector("#challenger-label").textContent = "Deterministic result";
    document.querySelector("#stage-value").textContent = "1";
    document.querySelector("#stage-comparison").innerHTML = "violation <strong>1 &gt; allowed maximum 0</strong>";
    document.querySelector("#challenge-result").textContent = "Claim refuted";
    document.querySelector("#agent-result").textContent = "Original claim refuted";
    document.querySelector("#agent-funds").textContent = "0 bounty returned";
    document.querySelector("#challenger-funds").textContent = "3.10 MON awarded";
    document.querySelector("#replay-copy").textContent = "The bound rule returned 1. The contract recorded the threshold breach and credited the challenger; the credit was then withdrawn.";
    action.textContent = "Verify the payout on Monad";
    summary.hidden = false;
  }
}

function advanceReplay() {
  if (replayStage === "claim") {
    setReplayStage("evidence");
  } else if (replayStage === "evidence") {
    setReplayStage("resolved");
    readProof();
  } else {
    document.querySelector("#verdict").scrollIntoView({ behavior: "smooth", block: "center" });
    readProof();
  }
}

document.querySelector("#commitment-id").textContent = COMMITMENT;
document.querySelector("#core-address").textContent = CORE;
document.querySelector("#registry-address").textContent = REGISTRY;
document.querySelector("#recomputer-address").textContent = RECOMPUTER;
document.querySelector("#decisive-receipt").href = `${EXPLORER}/tx/${transactions[2].hash}`;
document.querySelector("#refresh").addEventListener("click", readProof);
document.querySelector("#replay-action").addEventListener("click", advanceReplay);
document.querySelector("#reset-replay").addEventListener("click", () => setReplayStage("claim"));
document.querySelectorAll("[data-start-replay]").forEach((link) => {
  link.addEventListener("click", () => setReplayStage("claim"));
});
renderTimeline();
setReplayStage("claim");
