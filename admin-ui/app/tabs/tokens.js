import { knownTokenAddresses, recordsOf } from "../data.js";
import { tokenLabel, tokenMeta, tokenUsage } from "../model.js";
import { $, emptyState, entityCard } from "../ui.js";

export function renderTokens() {
  const registered = new Map(recordsOf("Managed token").map((record) => [String(record.id).toLowerCase(), record]));
  const cards = knownTokenAddresses().map((address) => {
    const meta = tokenMeta(address);
    const configRecord = registered.get(address.toLowerCase());
    const config = configRecord?.value;
    return entityCard({
      eyebrow: configRecord ? "Registered Managed token" : "ERC-20 asset",
      title: `${meta.symbol} · ${meta.name}`,
      subtitle: `${meta.decimals ?? "?"} decimals`,
      status: configRecord ? (config.enabled ? "Enabled" : "Disabled") : "Known asset",
      statusClass: configRecord && !config.enabled ? "warning" : "",
      facts: [
        ["Protocol role", configRecord ? "Managed token" : "External asset"],
        ["Registered decimals", configRecord ? Number(config.decimals) : "Not applicable"],
        ["Used by", tokenUsage(address) || "No configuration yet"],
      ],
      id: address,
      idLabel: "Contract address",
    });
  });
  $("#tokens-list").innerHTML = cards.length ? cards.join("") : emptyState("No tokens discovered. Deploy local tokens or track an ERC-20 address.");
}
