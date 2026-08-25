import { VAULT_KINDS } from "../config.js";
import { recordsOf } from "../data.js";
import { addressLabel, tokenMeta, vaultPurpose } from "../model.js";
import { $, emptyState, entityCard } from "../ui.js";
import { enumValue, formatTokenAmount } from "../utils.js";

export function renderVaults() {
  const cards = recordsOf("Vault").map((record) => {
    const value = record.value;
    const kind = VAULT_KINDS[enumValue(value.kind)];
    const balances = Object.entries(record.balances || {}).filter(([, balance]) => balance > 0n).map(([token, balance]) => {
      const meta = tokenMeta(token);
      return [meta.symbol, formatTokenAmount(balance, meta.decimals)];
    });
    return entityCard({
      eyebrow: `${kind} vault`,
      title: `${kind} vault #${value.vaultId}`,
      subtitle: vaultPurpose(enumValue(value.kind)),
      status: "Configured",
      facts: [
        ["Purpose", kind],
        ["Withdrawal destination", addressLabel(value.withdrawalDestination)],
        ["Refill target", `${Number(value.refillTargetBps) / 100}%`],
        ...(balances.length ? balances.map(([symbol, amount]) => [`${symbol} balance`, amount]) : [["Balances", "Empty"]]),
      ],
      id: record.id,
      idLabel: "Vault ID",
    });
  });
  $("#vaults-list").innerHTML = cards.length ? cards.join("") : emptyState("No vaults yet. Create a vault for fees, proceeds, liquidity, or initialize a Buffer.");
}
