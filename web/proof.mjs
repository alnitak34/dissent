function sameHex(left, right) {
  return typeof left === "string" && typeof right === "string" && left.toLowerCase() === right.toLowerCase();
}

function indexedAddress(address) {
  return `0x${address.slice(2).toLowerCase().padStart(64, "0")}`;
}

function dataWords(data) {
  if (typeof data !== "string" || !data.startsWith("0x")) return [];
  return data.slice(2).match(/.{64}/g) ?? [];
}

export function hasSuccessfulChallenge(receipt, expected) {
  return receipt?.logs?.some((log) => {
    if (!sameHex(log.address, expected.core)) return false;
    if (!sameHex(log.topics?.[0], expected.eventTopic)) return false;
    if (!sameHex(log.topics?.[1], expected.commitment)) return false;
    if (!sameHex(log.topics?.[2], indexedAddress(expected.challenger))) return false;
    const words = dataWords(log.data);
    return words.length === 4 && BigInt(`0x${words[0]}`) === expected.newValue &&
      BigInt(`0x${words[1]}`) === expected.threshold && BigInt(`0x${words[2]}`) === expected.payout;
  }) ?? false;
}

export function hasWithdrawal(receipt, expected) {
  return receipt?.logs?.some((log) => {
    if (!sameHex(log.address, expected.core)) return false;
    if (!sameHex(log.topics?.[0], expected.eventTopic)) return false;
    if (!sameHex(log.topics?.[1], indexedAddress(expected.beneficiary))) return false;
    const words = dataWords(log.data);
    return words.length === 1 && BigInt(`0x${words[0]}`) === expected.amount;
  }) ?? false;
}
