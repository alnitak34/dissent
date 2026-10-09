#!/usr/bin/env bash
# Fork rehearsal of the Aqueous early-release demonstration. Nothing here can reach mainnet: every
# transaction goes to a local anvil fork of Monad at a pinned block, and senders are impersonated.
#
#   MONAD_RPC_URL=<archive-capable Monad RPC> script/demo/rehearse-aqueous-early-release.sh
#
# Needs Foundry 1.8.1 (forge, cast, anvil on PATH), jq and bash 4+. Any failed step stops the run.
set -euo pipefail
cd "$(dirname "$0")/../.."

FORK_BLOCK="${FORK_BLOCK:-111847000}"
UPSTREAM="${MONAD_RPC_URL:-https://rpc.monad.xyz}"
PORT="${PORT:-8547}"
RPC="http://127.0.0.1:$PORT"
S=script/AqueousEarlyReleaseDemo.s.sol

export DEMO_AGENT=0xDB6c6340342e71A63cD11Ebac2185204b7777777
export DEMO_BUYER=0x27a8ae37f59BDcd147b09dDc1F35Ac64697c1F92
# TEST-ONLY placeholder challenger: keccak256("dissent.demo.challenger.TEST-ONLY-PLACEHOLDER"), no known key.
export DEMO_CHALLENGER="0x$(cast keccak 'dissent.demo.challenger.TEST-ONLY-PLACEHOLDER' | tail -c 41)"
export DEMO_REHEARSAL=true
export DEMO_REWARD_WEI="${DEMO_REWARD_WEI:-500000000000000000}" # 0.5 MON
export DEMO_JOB_SALT="$(cast keccak 'kanmani.dissent.demo.aqueous-early-release.v1')"
export DEMO_AGENT_SALT="${DEMO_AGENT_SALT:-$(cast keccak "agent-rehearsal-$RANDOM-$(date +%s%N)")}"
export DEMO_CHALLENGER_SALT="${DEMO_CHALLENGER_SALT:-$(cast keccak "challenger-rehearsal-$RANDOM-$(date +%s%N)")}"
CURATOR=0xa3aB9C3697F1964A8082330103C5DCaaA3B1263A

terms_hash="$(cast keccak 0x"$(od -An -v -tx1 docs/demo/aqueous-early-release.terms.txt | tr -d ' \n')")"
[[ "$terms_hash" == 0x6661ad444cb7963a313a077b89755439c73b96fc48a459bedeb52b42c1057db7 ]] || { echo "terms file changed: $terms_hash"; exit 1; }

# The port must be free: otherwise the steps could talk to some other node.
if cast chain-id --rpc-url "$RPC" >/dev/null 2>&1; then echo "port $PORT already answers RPC; refusing to reuse it"; exit 1; fi
anvil --fork-url "$UPSTREAM" --fork-block-number "$FORK_BLOCK" --port "$PORT" --auto-impersonate --silent &
ANVIL=$!
trap 'kill $ANVIL 2>/dev/null || true' EXIT
for _ in $(seq 60); do
  kill -0 "$ANVIL" 2>/dev/null || { echo "anvil exited before it was ready"; exit 1; }
  cast chain-id --rpc-url "$RPC" >/dev/null 2>&1 && break
  sleep 1
done
kill -0 "$ANVIL" 2>/dev/null || { echo "anvil is not running"; exit 1; }

# Check the node is the fork this script started, not only that it reports chain id 143.
info=$(cast rpc anvil_nodeInfo --rpc-url "$RPC")
[[ "$(jq -r .environment.chainId <<<"$info")" == 143 ]] || { echo "fork is not chain 143"; exit 1; }
[[ "$(jq -r .forkConfig.forkBlockNumber <<<"$info")" == "$FORK_BLOCK" ]] || { echo "fork block mismatch"; exit 1; }
[[ "$(jq -r .forkConfig.forkUrl <<<"$info")" == "$UPSTREAM" ]] || { echo "fork url mismatch"; exit 1; }
[[ "$(cast block-number --rpc-url "$RPC")" == "$FORK_BLOCK" ]] || { echo "fork head is not the pinned block"; exit 1; }
fork_hash=$(cast block "$FORK_BLOCK" -f hash --rpc-url "$RPC")
[[ "$fork_hash" == "$(cast block "$FORK_BLOCK" -f hash --rpc-url "$UPSTREAM")" ]] || { echo "fork block hash differs from upstream"; exit 1; }

echo "fork of Monad mainnet at block $FORK_BLOCK (hash $fork_hash), chain id 143, anvil pid $ANVIL"
echo "terms hash $terms_hash"
echo "test-only challenger $DEMO_CHALLENGER"
echo

GAS_REPORT=()
record() { # name, tx hash
  local used limit
  used=$(cast receipt "$2" gasUsed --rpc-url "$RPC")
  limit=$(cast tx "$2" gas --rpc-url "$RPC")
  GAS_REPORT+=("$1|$2|$used|$limit")
}
RUN_FILE="broadcast/AqueousEarlyReleaseDemo.s.sol/143/run-latest.json"
SEEN=" "
step() { # name, contract, sender
  local name=$1 contract=$2 sender=$3 out code hash nonce_before nonce_after from st
  echo "== $name (signer $sender)"
  rm -f "$RUN_FILE" # a stale run file can never be read as this step's result
  nonce_before=$(cast nonce "$sender" --rpc-url "$RPC")
  set +e
  out=$(forge script "$S:$contract" --rpc-url "$RPC" --broadcast --unlocked --sender "$sender" --slow 2>&1)
  code=$?
  set -e
  grep -E "^\s+(policy id|job id|simulated commitment id|txRequired|minGasBackedReward|base value|base gas|window ends|agent paid|recompute with|sealed at|status Challenged|withdrawn)|^\s+0x[0-9a-f]{64}$" <<<"$out" || true
  if [[ $code -ne 0 ]]; then echo "$out" | tail -20; echo "step failed: forge exited $code"; exit 1; fi
  [[ -s "$RUN_FILE" ]] || { echo "step failed: forge wrote no run file"; exit 1; }
  [[ "$(jq '.receipts | length' "$RUN_FILE")" == 1 ]] || { echo "step failed: expected exactly one transaction"; exit 1; }
  hash=$(jq -r '.receipts[0].transactionHash' "$RUN_FILE")
  [[ "$SEEN" != *" $hash "* ]] || { echo "step failed: receipt $hash was already used by an earlier step"; exit 1; }
  from=$(cast tx "$hash" from --rpc-url "$RPC")
  [[ "${from,,}" == "${sender,,}" ]] || { echo "step failed: $hash was sent by $from, not $sender"; exit 1; }
  [[ "$(cast tx "$hash" nonce --rpc-url "$RPC")" == "$nonce_before" ]] || { echo "step failed: unexpected nonce"; exit 1; }
  nonce_after=$(cast nonce "$sender" --rpc-url "$RPC")
  [[ $nonce_after -eq $((nonce_before + 1)) ]] || { echo "step failed: sender nonce moved by $((nonce_after - nonce_before))"; exit 1; }
  st=$(cast receipt "$hash" status --rpc-url "$RPC")
  [[ "$st" == true || "$st" == 1* ]] || { echo "step failed: $hash reverted"; exit 1; }
  SEEN+="$hash "
  record "$name" "$hash"
  LAST_HASH=$hash
}

# Test funding on the fork only. On mainnet the agent sends the buyer gas money (step 0 below) and the
# curator and challenger use their own MON.
cast rpc anvil_setBalance "$DEMO_CHALLENGER" 0xDE0B6B3A7640000 --rpc-url "$RPC" >/dev/null # 1 MON, test only
cast rpc anvil_setBalance "$CURATOR" 0xDE0B6B3A7640000 --rpc-url "$RPC" >/dev/null           # 1 MON, test only

echo "== 0 agent sends the buyer 0.1 MON for gas (approve, open, release)"
h=$(cast send "$DEMO_BUYER" --value 0.1ether --from "$DEMO_AGENT" --unlocked --rpc-url "$RPC" --json | jq -r .transactionHash)
[[ "$(cast receipt "$h" status --rpc-url "$RPC")" == true && "$(cast tx "$h" from --rpc-url "$RPC" | tr A-F a-f)" == "${DEMO_AGENT,,}" ]] || { echo "top-up failed"; exit 1; }
SEEN+="$h "
record "0 agent tops up buyer gas" "$h"

step "1 curator registers policy" DemoRegisterPolicy "$CURATOR"
step "2 buyer approves 0.10 USDC" DemoBuyerApprove "$DEMO_BUYER"
step "3 buyer opens flat job" DemoBuyerOpenJob "$DEMO_BUYER"
step "4 agent commits bounty" DemoAgentCommit "$DEMO_AGENT"
export DEMO_COMMITMENT_ID=$(cast receipt "$LAST_HASH" --rpc-url "$RPC" --json \
  | jq -r --arg core 0x9d673a8b5efe76d42593b45972fa0426648967e1 '[.logs[] | select((.address|ascii_downcase)==$core)][-1].topics[1]')
[[ "$DEMO_COMMITMENT_ID" =~ ^0x[0-9a-f]{64}$ ]] || { echo "no Committed event in the commit receipt"; exit 1; }
echo "   commitment id from the Committed event: $DEMO_COMMITMENT_ID"
step "5 buyer releases early" DemoBuyerReleaseEarly "$DEMO_BUYER"
step "6 challenger seals" DemoChallengerSeal "$DEMO_CHALLENGER"
cast rpc anvil_mine 5 --rpc-url "$RPC" >/dev/null
echo "   mined 5 blocks (REVEAL_DELAY_BLOCKS)"
step "7 challenger reveals" DemoChallengerReveal "$DEMO_CHALLENGER"
step "8 challenger withdraws" DemoChallengerWithdraw "$DEMO_CHALLENGER"

echo
echo "== final state"
JOB=$(cast call 0xd75f7786D0DD42c8F161Bd78E87D37001044Fc32 "jobIdFor(address,address,bytes32)(bytes32)" "$DEMO_BUYER" "$DEMO_AGENT" "$DEMO_JOB_SALT" --rpc-url "$RPC")
echo "job $JOB state (3 = Settled): $(cast call 0xd75f7786D0DD42c8F161Bd78E87D37001044Fc32 'jobs(bytes32)((address,uint64,uint8,address,uint64,address,uint128,uint128,bytes32,bytes32))' "$JOB" --rpc-url "$RPC" | tr -d '()' | cut -d, -f3 | tr -d ' ')"
echo "commitment status (2 = Challenged): $(cast call 0x9D673a8B5EfE76D42593b45972Fa0426648967E1 'getCommitment(bytes32)((address,address,bytes32,bytes32,bytes32,bytes32,bytes32,int256,int256,uint128,uint128,uint64,uint64,uint32,uint32,uint32,uint32,uint256,uint8,uint8))' "$DEMO_COMMITMENT_ID" --rpc-url "$RPC" | tr -d '()' | awk -F', ' '{print $NF}')"
echo "challenger credit left: $(cast call 0x9D673a8B5EfE76D42593b45972Fa0426648967E1 'credits(address)(uint256)' "$DEMO_CHALLENGER" --rpc-url "$RPC")"

PRICE=$(cast gas-price --rpc-url "$UPSTREAM")
echo
echo "== gas (Monad charges the gas limit; cost at today's mainnet gas price $(cast from-wei "$PRICE" gwei) gwei)"
printf '%-30s %10s %10s %14s\n' step used limit "cost MON"
for r in "${GAS_REPORT[@]}"; do
  IFS='|' read -r name _ used limit <<<"$r"
  printf '%-30s %10s %10s %14s\n' "$name" "$used" "$limit" "$(cast from-wei $((limit * PRICE)))"
done
