/** Local proposal only: not registered in upstream ATLAS. */
import type { Mapping } from "./src/ladder/parse.ts";

export const dissentWithdrawalReceipt: Mapping = {
  name: "dissent-withdrawal-receipt.v1",
  induced: "2026-10-15",
  note: "Exact total native withdrawal; reward/deposit split is not verified",
  matches: d => d.type === "dissent-withdrawal-receipt",
  extract(d) {
    const address = (v: unknown) => typeof v === "string" && /^0x[0-9a-fA-F]{40}$/.test(v) && !/^0x0{40}$/i.test(v);
    if (d.version !== 1 || d.chainId !== 143 || d.asset !== "native" ||
        typeof d.txHash !== "string" || !/^0x[0-9a-fA-F]{64}$/.test(d.txHash) ||
        !address(d.core) || !address(d.recipient) ||
        typeof d.amountAtomic !== "string" || !/^[1-9][0-9]*$/.test(d.amountAtomic)) {
      return { kind: "unparsed", reason: "Dissent v1 requires Monad 143, native asset, valid addresses/hash and a positive atomic integer string" };
    }
    return { kind: "claim", mapping: this.name, claim: {
      network: d.chainId, txHash: d.txHash, recipient: d.recipient,
      payer: d.core, amount: d.amountAtomic, token: d.asset,
    } };
  },
};
