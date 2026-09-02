import { OFFER_DIRECTIONS, OFFER_FLOWS, ZERO_BYTES32 } from "../config.js";
import { recordsOf } from "../data.js";
import { entityLabel, offerManagedToken, tokenLabel } from "../model.js";
import { $, emptyState, entityCard } from "../ui.js";
import { enumValue } from "../utils.js";

export function renderOffers() {
  const cards = recordsOf("Offer").map((record) => {
    const value = record.value;
    const managedToken = offerManagedToken(value);
    const pricer = recordsOf("Pricer").find((candidate) => candidate.value.managedToken.toLowerCase() === managedToken?.toLowerCase());
    return entityCard({
      eyebrow: OFFER_FLOWS[enumValue(value.flow)],
      title: `${tokenLabel(value.tokenIn)} → ${tokenLabel(value.tokenOut)}`,
      subtitle: OFFER_DIRECTIONS[enumValue(value.direction)],
      status: value.disabled ? "Disabled" : "Enabled",
      statusClass: value.disabled ? "warning" : "",
      facts: [
        ["Input", `${tokenLabel(value.tokenIn)} · ${value.tokenInDecimals} decimals`],
        ["Output", `${tokenLabel(value.tokenOut)} · ${value.tokenOutDecimals} decimals`],
        ["Flow", OFFER_FLOWS[enumValue(value.flow)]],
        ["Pricer (automatic)", pricer ? entityLabel("Pricer", pricer.id) : "Missing"],
        ["Quoter", entityLabel("Quoter", value.quoterId)],
        ["Fee policy", entityLabel("Fee config", value.feeConfigId)],
        ["Proceeds", entityLabel("Vault", value.proceedsVaultId)],
        ["Liquidity", value.liquidityVaultId === ZERO_BYTES32 ? "None" : entityLabel("Vault", value.liquidityVaultId)],
      ],
      id: record.id,
      idLabel: "Offer config ID",
    });
  });
  $("#offers-list").innerHTML = cards.length ? cards.join("") : emptyState("No offers yet. The form above will only offer compatible existing dependencies.");
}

export function renderDerivedPricer() {
  const form = $("#create-offer-form");
  const tokenIn = form.elements.tokenIn.value;
  const tokenOut = form.elements.tokenOut.value;
  const managedToken = [tokenIn, tokenOut].find((address) => recordsOf("Managed token").some((record) => String(record.id).toLowerCase() === address?.toLowerCase()));
  const pricer = managedToken && recordsOf("Pricer").find((record) => record.value.managedToken.toLowerCase() === managedToken.toLowerCase());
  $("#derived-pricer").querySelector("strong").textContent = pricer ? entityLabel("Pricer", pricer.id) : managedToken ? "Missing USD pricer" : "Pair must contain one Managed token";
}
