const RPC_URL = "https://testnet-rpc.monad.xyz";
const EXPLORER = "https://testnet.monadvision.com";
const CORE = "0x6dCD184c9c0db42FCD0De731F9a2855b38916758";
const RECOMPUTER = "0x2a26e33CD2118a2D340bbA810e23a8E5CfdE8E38";
const CHALLENGER = "0x00cf6ceC697E3DCB88a5972Ef083B423dfC00A02";
const COMMITMENT = "0xd8c13c6574b6c3af196154a835a93a03bcf7ffe9e4212c2fb81f8c21d5e22811";

const transactions = [
  { name: "Commit", detail: "Agent stakes 3 MON", hash: "0xc2215f552c299527154055fc9e706b5fe0d5e9ddf387d9ff5c8670bf52304f5f" },
  { name: "Seal", detail: "Evidence is hidden", hash: "0x593b6badea3209085196e3ac3b7d1a8b81f8c14f64e197e3d39e7c5d06dad6d8" },
  { name: "Reveal", detail: "Threshold is broken", hash: "0x427b5ca4e64453bf00591a364c8a0fe9d91cafffa67a4af1a520fe1f8d1e188e" },
  { name: "Withdraw", detail: "3.1 MON is collected", hash: "0x621151e057ceb3e52d8febf2e1e91eba77fbd5f9a901eb586d62d0fe4fc7c61f" },
];

const selectors = {
  commitment: `0x839df945${COMMITMENT.slice(2)}`,
  credits: `0xfe5ff468${CHALLENGER.slice(2).padStart(64, "0")}`,
  escrowed: "0x01522b1e",
};

let requestId = 0;

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
    const confirmed = receipt?.status === "0x1";
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
  document.querySelector("#verdict-detail").textContent = "Four receipts and the final contract state are being checked.";

  try {
    const [receipts, commitmentData, creditData, escrowData] = await Promise.all([
      Promise.all(transactions.map((tx) => rpc("eth_getTransactionReceipt", [tx.hash]))),
      rpc("eth_call", [{ to: CORE, data: selectors.commitment }, "latest"]),
      rpc("eth_call", [{ to: CORE, data: selectors.credits }, "latest"]),
      rpc("eth_call", [{ to: CORE, data: selectors.escrowed }, "latest"]),
    ]);

    renderTimeline(receipts);
    const allConfirmed = receipts.every((receipt) => receipt?.status === "0x1");
    const status = Number.parseInt(lastWord(commitmentData), 16);
    const credit = BigInt(creditData);
    const escrow = BigInt(escrowData);
    const complete = allConfirmed && status === 2 && credit === 0n && escrow === 0n;

    if (!complete) {
      throw new Error("The current state does not match the recorded completed challenge.");
    }

    verdict.dataset.state = "success";
    verdict.querySelector(".verdict-icon").textContent = "✓";
    verdict.querySelector(".label").textContent = "Live onchain state";
    verdict.querySelector("h3").textContent = "Claim refuted · payout withdrawn";
    document.querySelector("#verdict-detail").textContent = "All four transactions are confirmed. Commitment status is Challenged; protocol credit and escrow are zero.";
  } catch (error) {
    verdict.dataset.state = "error";
    verdict.querySelector(".verdict-icon").textContent = "!";
    verdict.querySelector(".label").textContent = "RPC check unavailable";
    verdict.querySelector("h3").textContent = "The live state could not be confirmed";
    document.querySelector("#verdict-detail").textContent = `${error.message} Use the transaction links below to inspect the proof.`;
    renderTimeline();
  } finally {
    refresh.disabled = false;
  }
}

document.querySelector("#commitment-id").textContent = COMMITMENT;
document.querySelector("#core-address").textContent = CORE;
document.querySelector("#recomputer-address").textContent = RECOMPUTER;
document.querySelector("#refresh").addEventListener("click", readProof);
renderTimeline();
readProof();
