const RPC_URL = "https://testnet-rpc.monad.xyz";
const EXPLORER = "https://testnet.monadvision.com";
const CORE = "0x460f9F624da9e23c705c610E1263bf3641bCce23";
const RECOMPUTER = "0x10EE57C2c75308118C527d909c6FDCF77BBaCb2d";
const CHALLENGER = "0x00cf6ceC697E3DCB88a5972Ef083B423dfC00A02";
const AGENT = "0xa3aB9C3697F1964A8082330103C5DCaaA3B1263A";
const COMMITMENT = "0xeabab853de85ea81b5cb837ac289b03995e33063d0ce8b457d531a390a2f4bd0";
const CHALLENGE_SUCCEEDED = "0x91c1883709a1e9edb879e595583d9d3b74a04df0fbaf5b3eb92587fadfc17e78";
const PAYOUT = 3100000000000000000n;

const transactions = [
  { name: "Commit", detail: "Agent locks 3 test MON", hash: "0x82fa86b28ddcbc86673fa48e1cd30132a6408f99924b78d0557c885b101dcaa6", block: 62934464 },
  { name: "First seal", detail: "Challenger locks 0.1 test MON", hash: "0x5fa99ebdeea86d137db7387c6b33e6fa17a896b5182eec9244e90a346c30fa19", block: 62935135 },
  { name: "Expired seal", detail: "Unrevealed deposit credited to agent", hash: "0x763c3e691570aa40a62a679593e09d9f24b4ae5cfe883f86b92d587c58f0473d", block: 62944009 },
  { name: "Second seal", detail: "New hidden evidence, new deposit", hash: "0xef46f42f23fe0bc9dc7e400b0aa8083e4fa249c2a241bc829258b99b169eaa78", block: 62945710 },
  { name: "Reveal", detail: "Violation 1 exceeds threshold 0", hash: "0xeb4e80fdd0aba0e29ef8cb6abc81ac5b6ba475d5bdbcba6bd757a9cbcebbfb5f", block: 62947743 },
  { name: "Challenger withdraws", detail: "3.1 test MON credit collected", hash: "0x59d57ad7a1d4dae42f0c0eff9d4d748466c6b61f5e848824858e4e113784bec1", block: 62949761 },
  { name: "Agent withdraws", detail: "Expired seal's 0.1 test MON collected", hash: "0x5d6e96ce0b801de23d57d680dfa57022039fd41330033c448a803ece89412212", block: 62950146 },
];

const selectors = {
  commitment: `0x839df945${COMMITMENT.slice(2)}`,
  credits: `0xfe5ff468${CHALLENGER.slice(2).padStart(64, "0")}`,
  agentCredits: `0xfe5ff468${AGENT.slice(2).padStart(64, "0")}`,
  escrowed: "0x01522b1e",
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

function hasSuccessfulChallenge(receipt) {
  return receipt?.logs?.some((log) => {
    if (log.address.toLowerCase() !== CORE.toLowerCase()) return false;
    if (log.topics[0]?.toLowerCase() !== CHALLENGE_SUCCEEDED) return false;
    if (log.topics[1]?.toLowerCase() !== COMMITMENT.toLowerCase()) return false;
    if (log.topics[2]?.toLowerCase() !== `0x${CHALLENGER.slice(2).toLowerCase().padStart(64, "0")}`) return false;
    const words = log.data.slice(2).match(/.{64}/g);
    return words?.length === 4 && BigInt(`0x${words[0]}`) === 1n &&
      BigInt(`0x${words[1]}`) === 0n && BigInt(`0x${words[2]}`) === PAYOUT;
  }) ?? false;
}

async function readProof() {
  const refresh = document.querySelector("#refresh");
  const verdict = document.querySelector("#verdict");
  refresh.disabled = true;
  verdict.dataset.state = "loading";
  verdict.querySelector(".verdict-icon").textContent = "···";
  verdict.querySelector(".label").textContent = "Reading Monad Testnet";
  verdict.querySelector("h3").textContent = "Checking the proof directly from the chain";
  document.querySelector("#verdict-detail").textContent = "Seven receipts, the ChallengeSucceeded event and the final contract state are being checked.";

  try {
    const [receipts, commitmentData, creditData, agentCreditData, escrowData] = await Promise.all([
      Promise.all(transactions.map((tx) => rpc("eth_getTransactionReceipt", [tx.hash]))),
      rpc("eth_call", [{ to: CORE, data: selectors.commitment }, "latest"]),
      rpc("eth_call", [{ to: CORE, data: selectors.credits }, "latest"]),
      rpc("eth_call", [{ to: CORE, data: selectors.agentCredits }, "latest"]),
      rpc("eth_call", [{ to: CORE, data: selectors.escrowed }, "latest"]),
    ]);

    renderTimeline(receipts);
    const allConfirmed = receipts.every((receipt, index) =>
      receipt?.status === "0x1" && Number.parseInt(receipt.blockNumber, 16) === transactions[index].block &&
      receipt.to?.toLowerCase() === CORE.toLowerCase());
    const status = Number.parseInt(lastWord(commitmentData), 16);
    const credit = BigInt(creditData);
    const agentCredit = BigInt(agentCreditData);
    const escrow = BigInt(escrowData);
    const complete = allConfirmed && hasSuccessfulChallenge(receipts[4]) &&
      status === 2 && credit === 0n && agentCredit === 0n && escrow === 0n;

    if (!complete) {
      throw new Error("The current state does not match the recorded completed challenge.");
    }

    verdict.dataset.state = "success";
    verdict.querySelector(".verdict-icon").textContent = "✓";
    verdict.querySelector(".label").textContent = "Live onchain state";
    verdict.querySelector("h3").textContent = "Claim refuted · payout withdrawn";
    document.querySelector("#verdict-detail").textContent = "Seven receipts and the 1 > 0 payout event confirmed. Status: Challenged. Both credits and escrow: zero after withdrawal.";
  } catch (error) {
    verdict.dataset.state = "error";
    verdict.querySelector(".verdict-icon").textContent = "!";
    verdict.querySelector(".label").textContent = "Verification incomplete";
    verdict.querySelector("h3").textContent = "The live state could not be confirmed";
    document.querySelector("#verdict-detail").textContent = `${error.message} Use the transaction links below to inspect the proof.`;
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
    document.querySelector("#challenger-label").textContent = "Second seal · hidden evidence";
    document.querySelector("#stage-value").textContent = "SEALED";
    document.querySelector("#stage-comparison").textContent = "Hidden until the reveal window";
    document.querySelector("#challenge-result").textContent = "Waiting";
    document.querySelector("#agent-result").textContent = "Claim stands";
    document.querySelector("#agent-funds").textContent = "3.00 MON locked";
    document.querySelector("#challenger-funds").textContent = "0.10 MON deposit";
    document.querySelector("#replay-copy").textContent = "An earlier seal expired. The challenger sealed a second attempt; its evidence remains hidden until reveal.";
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
document.querySelector("#recomputer-address").textContent = RECOMPUTER;
document.querySelector("#refresh").addEventListener("click", readProof);
document.querySelector("#replay-action").addEventListener("click", advanceReplay);
document.querySelector("#reset-replay").addEventListener("click", () => setReplayStage("claim"));
document.querySelectorAll("[data-start-replay]").forEach((link) => {
  link.addEventListener("click", () => setReplayStage("claim"));
});
renderTimeline();
setReplayStage("claim");
