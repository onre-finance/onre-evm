import { recordsOf } from "../data.js";
import { $, openTab } from "../ui.js";

export function renderOverview(onTransactions) {
  const summaries = [
    ["tokens", recordsOf("OnRe token").length, "OnRe tokens"],
    ["pricing", recordsOf("Pricer").length, "Pricers"],
    ["buffer", recordsOf("Buffer").length, "Buffers"],
    ["quoters", recordsOf("Quoter").length, "Quoters"],
    ["vaults", recordsOf("Vault").length, "Vaults"],
    ["fees", recordsOf("Fee config").length, "Fee configs"],
    ["offers", recordsOf("Offer").length, "Offers"],
  ];
  $("#entity-summary").innerHTML = summaries.map(([tab, count, label]) => `
    <button class="summary-card" data-open-tab="${tab}"><strong>${count}</strong><span>${label}</span></button>`).join("");
  document.querySelectorAll(".summary-card").forEach((button) => {
    button.addEventListener("click", () => openTab(button.dataset.openTab, onTransactions));
  });
}
