import assert from "node:assert/strict";
import test from "node:test";

import { hasSuccessfulChallenge, hasWithdrawal } from "./proof.mjs";

const CORE = "0x686164f708b87d1A63bEE8Aa3130298246690a87";
const CHALLENGER = "0x00cf6ceC697E3DCB88a5972Ef083B423dfC00A02";
const COMMITMENT = "0x84f00753bfca460938625e9e0c84d0f856065ac9722f5ac3146ac7e71342389d";
const CHALLENGE_TOPIC = "0x91c1883709a1e9edb879e595583d9d3b74a04df0fbaf5b3eb92587fadfc17e78";
const WITHDRAWN_TOPIC = "0x7084f5476618d8e60b11ef0d7d3f06914655adb8793e28ff7f018d4c76d505d5";

const word = (value) => value.toString(16).padStart(64, "0");
const addressTopic = (address) => `0x${address.slice(2).toLowerCase().padStart(64, "0")}`;

test("accepts the exact successful challenge event", () => {
  const receipt = { logs: [{
    address: CORE,
    topics: [CHALLENGE_TOPIC, COMMITMENT, addressTopic(CHALLENGER)],
    data: `0x${word(1n)}${word(0n)}${word(3100000000000000000n)}${word(123n)}`,
  }] };
  assert.equal(hasSuccessfulChallenge(receipt, {
    core: CORE,
    eventTopic: CHALLENGE_TOPIC,
    commitment: COMMITMENT,
    challenger: CHALLENGER,
    newValue: 1n,
    threshold: 0n,
    payout: 3100000000000000000n,
  }), true);
});

test("rejects a challenge event with the wrong payout", () => {
  const receipt = { logs: [{
    address: CORE,
    topics: [CHALLENGE_TOPIC, COMMITMENT, addressTopic(CHALLENGER)],
    data: `0x${word(1n)}${word(0n)}${word(1n)}${word(123n)}`,
  }] };
  assert.equal(hasSuccessfulChallenge(receipt, {
    core: CORE,
    eventTopic: CHALLENGE_TOPIC,
    commitment: COMMITMENT,
    challenger: CHALLENGER,
    newValue: 1n,
    threshold: 0n,
    payout: 3100000000000000000n,
  }), false);
});

test("accepts only the exact beneficiary and withdrawal amount", () => {
  const amount = 3100000000000000000n;
  const receipt = { logs: [{
    address: CORE.toLowerCase(),
    topics: [WITHDRAWN_TOPIC, addressTopic(CHALLENGER)],
    data: `0x${word(amount)}`,
  }] };
  const expected = { core: CORE, eventTopic: WITHDRAWN_TOPIC, beneficiary: CHALLENGER, amount };
  assert.equal(hasWithdrawal(receipt, expected), true);
  assert.equal(hasWithdrawal(receipt, { ...expected, amount: amount - 1n }), false);
});
