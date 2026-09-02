import { PRICING_DENOMINATIONS } from "../config.js";
import { recordsOf } from "../data.js";
import { tokenLabel } from "../model.js";
import { $, emptyState, entityCard } from "../ui.js";
import { enumValue, formatDate, formatDuration, formatPercentScaled, formatUsdPrice } from "../utils.js";

export function renderPricing() {
  const cards = recordsOf("Pricer").map((record) => {
    const value = record.value;
    const count = Number(value.vectorCount);
    const vectors = (value.vectors || []).slice(0, count);
    const vectorFacts = vectors.length
      ? vectors.map((vector, index) => [
        `Vector ${index + 1}`,
        `${formatUsdPrice(vector.basePrice)} base · ${formatPercentScaled(vector.apr)} APR · activates ${formatDate(vector.startTime)} · compounds from ${formatDate(vector.baseTime)} · ${formatDuration(vector.priceFixDuration)} steps`,
      ])
      : [["Pricing vectors", "None configured"]];
    return entityCard({
      eyebrow: "USD pricer",
      title: `${tokenLabel(value.managedToken)} / ${PRICING_DENOMINATIONS[enumValue(value.denomination)]}`,
      subtitle: `${count} pricing vector${count === 1 ? "" : "s"}`,
      status: value.disabled ? "Disabled" : vectors.length ? "Active" : "Needs vector",
      statusClass: value.disabled || !vectors.length ? "warning" : "",
      facts: [
        ["Managed token", tokenLabel(value.managedToken)],
        ["Denomination", PRICING_DENOMINATIONS[enumValue(value.denomination)]],
        ["Current price", record.currentPrice ? formatUsdPrice(record.currentPrice) : "No active vector"],
        ...vectorFacts,
      ],
      id: record.id,
      idLabel: "Pricer ID",
    });
  });
  $("#pricing-list").innerHTML = cards.length ? cards.join("") : emptyState("No pricers yet. Register a Managed token, then create its USD pricer.");
}
