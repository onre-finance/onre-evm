import { zeroAddress } from "viem";
import { APR_SCALE } from "../config.js";
import { recordById, recordsOf } from "../data.js";
import { addressLabel, entityLabel, tokenLabel, tokenMeta } from "../model.js";
import { state } from "../state.js";
import { $, emptyState, entityCard } from "../ui.js";
import { formatBps, formatDate, formatPercentScaled, formatTokenAmount, formatUsdPrice } from "../utils.js";

export function renderBuffers() {
  const cards = recordsOf("Buffer").map((record) => {
    const value = record.value;
    const active = record.controller
      && record.controller !== zeroAddress
      && record.controller.toLowerCase() === state.diamondAddress.toLowerCase();
    return entityCard({
      eyebrow: "Token-scoped Buffer",
      title: `${tokenLabel(record.id)} Buffer`,
      subtitle: `Last accrued ${formatDate(value.lastAccrualTimestamp)}`,
      status: active ? "Active" : "Needs activation",
      statusClass: active ? "" : "warning",
      facts: [
        ["Controller", addressLabel(record.controller)],
        ["Gross APR", formatPercentScaled(value.grossApr)],
        ["Management fee", formatBps(value.managementFeeBasisPoints)],
        ["Performance fee", formatBps(value.performanceFeeBasisPoints)],
        ["High-watermark check", value.performanceFeeHighWatermarkEnabled ? "Enabled" : "Disabled"],
        ["Performance high watermark", value.performanceFeeHighWatermark ? formatUsdPrice(value.performanceFeeHighWatermark) : "Not seeded"],
        ["Previous supply", formatTokenAmount(value.previousSupply, tokenMeta(record.id).decimals)],
        ["Reserve vault", entityLabel("Vault", value.reserveVaultId)],
        ["Management fees", entityLabel("Vault", value.managementFeeVaultId)],
        ["Performance fees", entityLabel("Vault", value.performanceFeeVaultId)],
      ],
      id: record.id,
      idLabel: "OnRe token",
    });
  });
  $("#buffer-list").innerHTML = cards.length
    ? cards.join("")
    : emptyState("No Buffer initialized yet. Register a token and create active USD pricing first.");
  syncBufferForm();
}

export function syncBufferForm() {
  const form = $("#configure-buffer-form");
  const record = recordById("Buffer", form.elements.onReToken.value);
  if (!record) return;
  const value = record.value;
  form.elements.grossApr.value = String(Number(value.grossApr) * 100 / APR_SCALE);
  form.elements.managementFee.value = String(Number(value.managementFeeBasisPoints) / 100);
  form.elements.performanceFee.value = String(Number(value.performanceFeeBasisPoints) / 100);
  form.elements.highWatermark.checked = value.performanceFeeHighWatermarkEnabled;
  setDestination(form.elements.reserveDestination, value.reserveVaultId);
  setDestination(form.elements.managementFeeDestination, value.managementFeeVaultId);
  setDestination(form.elements.performanceFeeDestination, value.performanceFeeVaultId);
}

function setDestination(input, vaultId) {
  const destination = recordById("Vault", vaultId)?.value.withdrawalDestination;
  input.value = destination && destination !== zeroAddress ? destination : state.bossAccount || input.value;
  input.dataset.autofilled = "true";
}
