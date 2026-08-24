import { zeroAddress } from "viem";
import { QUOTER_KINDS } from "../config.js";
import { recordsOf } from "../data.js";
import { tokenLabel } from "../model.js";
import { $, emptyState, entityCard } from "../ui.js";
import { enumValue, formatBps, formatDuration } from "../utils.js";

export function renderQuoters() {
  const rfqStates = new Map(recordsOf("Prop RFQ").map((record) => [String(record.id).toLowerCase(), record.value]));
  const cards = recordsOf("Quoter").map((record) => {
    const value = record.value;
    const kind = enumValue(value.kind);
    const rfqState = rfqStates.get(String(record.id).toLowerCase());
    const configured = kind !== 2 || (rfqState && rfqState.assetToken && rfqState.assetToken !== zeroAddress);
    const facts = [
      ["Type", QUOTER_KINDS[kind]],
      ["Instance", `#${value.instanceId}`],
      ["Compatible flow", kind === 0 ? "Permissioned or Worker" : "Permissionless"],
    ];
    if (kind === 2) facts.push(
      ["Pair", configured ? `${tokenLabel(rfqState.assetToken)} ↔ ${tokenLabel(rfqState.onReToken)}` : "Not configured"],
      ["Peg haircut", configured ? formatBps(rfqState.config.curvePegHaircutBps) : "—"],
      ["Epoch", configured ? formatDuration(rfqState.config.epochDurationSeconds) : "—"],
      ["Current buy volume", configured ? rfqState.currentBuyValueStable.toString() : "—"],
      ["Current sell volume", configured ? rfqState.currentSellValueStable.toString() : "—"],
    );
    return entityCard({
      eyebrow: QUOTER_KINDS[kind],
      title: `${QUOTER_KINDS[kind]} #${value.instanceId}`,
      subtitle: kind === 2 && configured ? `${tokenLabel(rfqState.assetToken)} ↔ ${tokenLabel(rfqState.onReToken)}` : "Reusable quote engine",
      status: value.disabled ? "Disabled" : configured ? "Ready" : "Needs configuration",
      statusClass: value.disabled || !configured ? "warning" : "",
      facts,
      id: record.id,
      idLabel: "Quoter ID",
    });
  });
  $("#quoters-list").innerHTML = cards.length ? cards.join("") : emptyState("No quoters yet. Create a NAV or Proprietary RFQ quoter.");
}
