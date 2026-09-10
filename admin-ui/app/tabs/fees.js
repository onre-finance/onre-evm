import { recordsOf } from "../data.js";
import { entityLabel } from "../model.js";
import { $, emptyState, entityCard } from "../ui.js";
import { formatBps } from "../utils.js";

export function renderFees() {
  const cards = recordsOf("Fee config").map((record) => {
    const value = record.value;
    return entityCard({
      eyebrow: "Reusable fee policy",
      title: `Fee config #${value.feeConfigId}`,
      subtitle: `${formatBps(value.basisPoints)} of gross input`,
      status: value.enabled ? "Enabled" : "Disabled",
      statusClass: value.enabled ? "" : "warning",
      facts: [
        ["Percentage fee", formatBps(value.basisPoints)],
        ["Minimum fee", `${value.minimumFeeAmount} raw input units`],
        ["Destination", entityLabel("Vault", value.feeVaultId)],
      ],
      id: record.id,
      idLabel: "Fee config ID",
    });
  });
  $("#fees-list").innerHTML = cards.length ? cards.join("") : emptyState("No fee configurations yet. Create a Fee vault first.");
}
