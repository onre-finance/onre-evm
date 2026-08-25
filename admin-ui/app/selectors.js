import { getAddress, isAddress } from "viem";
import { OFFER_FLOWS, ZERO_BYTES32 } from "./config.js";
import { knownTokenAddresses, recordsOf } from "./data.js";
import { entityLabel, tokenLabel } from "./model.js";
import { state } from "./state.js";
import { $ } from "./ui.js";
import { enumValue, escapeHtml } from "./utils.js";

export function renderSelectOptions() {
  document.querySelectorAll("select[data-options]").forEach((select) => {
    setSelectOptions(select, optionsFor(select.dataset.options));
  });
  const form = $("#create-offer-form");
  const assets = optionsFor("asset-tokens");
  const onReTokens = optionsFor("onre-tokens");
  if (!form.dataset.defaultsApplied && assets.length && onReTokens.length) {
    const latestRfq = recordsOf("Prop RFQ")[0]?.value;
    const preferredAsset = latestRfq && assets.find((option) => String(option.value).toLowerCase() === latestRfq.assetToken.toLowerCase());
    const preferredOnRe = latestRfq && onReTokens.find((option) => String(option.value).toLowerCase() === latestRfq.onReToken.toLowerCase());
    form.elements.tokenIn.value = String((preferredAsset || assets[0]).value);
    form.elements.tokenOut.value = String((preferredOnRe || onReTokens[0]).value);
    form.dataset.defaultsApplied = "true";
  }
  setSelectOptions(form.elements.quoterId, compatibleQuoterOptions());
}

function setSelectOptions(select, options) {
  const current = select.value;
  const optional = select.dataset.optional === "true";
  const none = optional ? [{ value: ZERO_BYTES32, label: "None" }] : [];
  select.innerHTML = [...none, ...options].map((option) => `<option value="${escapeHtml(String(option.value))}">${escapeHtml(option.label)}</option>`).join("");
  if ([...select.options].some((option) => option.value === current)) select.value = current;
}

export function optionsFor(kind) {
  const addresses = knownTokenAddresses();
  const totals = addresses.reduce((counts, address) => {
    const label = tokenLabel(address);
    counts.set(label, (counts.get(label) || 0) + 1);
    return counts;
  }, new Map());
  const seen = new Map();
  const tokens = addresses.map((address) => {
    const label = tokenLabel(address);
    const occurrence = (seen.get(label) || 0) + 1;
    seen.set(label, occurrence);
    return { value: address, label: totals.get(label) > 1 ? `${label} · deployment ${occurrence}` : label };
  });
  if (kind === "tokens") return tokens;
  if (kind === "onre-tokens") return recordsOf("OnRe token").map((record) => ({ value: record.id, label: tokenLabel(record.id) }));
  if (kind === "buffer-candidates") {
    const initialized = new Set(recordsOf("Buffer").map((record) => String(record.id).toLowerCase()));
    return recordsOf("OnRe token")
      .filter((record) => !initialized.has(String(record.id).toLowerCase()))
      .map((record) => ({ value: record.id, label: tokenLabel(record.id) }));
  }
  if (kind === "asset-tokens") {
    const onRe = new Set(recordsOf("OnRe token").map((record) => String(record.id).toLowerCase()));
    return tokens.filter((option) => !onRe.has(String(option.value).toLowerCase()));
  }
  if (kind === "pricers") return recordsOf("Pricer").map((record) => ({ value: record.id, label: entityLabel("Pricer", record.id) }));
  if (kind === "rfq-quoters") return recordsOf("Quoter").filter((record) => enumValue(record.value.kind) === 2).map((record) => ({ value: record.id, label: entityLabel("Quoter", record.id) }));
  if (kind === "vaults") return recordsOf("Vault").map((record) => ({ value: record.id, label: entityLabel("Vault", record.id) }));
  if (kind === "fee-vaults") return vaultOptions(0);
  if (kind === "proceeds-vaults") return vaultOptions(1);
  if (kind === "liquidity-vaults") return vaultOptions(2);
  if (kind === "fees") return recordsOf("Fee config").map((record) => ({ value: record.id, label: entityLabel("Fee config", record.id) }));
  if (kind === "mintable-tokens") return mintableTokenAddresses().map((address) => ({ value: address, label: tokenLabel(address) }));
  if (kind === "executable-offers") return recordsOf("Offer")
    .filter((record) => !record.value.disabled && enumValue(record.value.flow) !== 2)
    .map((record) => ({
      value: record.id,
      label: `${tokenLabel(record.value.tokenIn)} → ${tokenLabel(record.value.tokenOut)} · ${OFFER_FLOWS[enumValue(record.value.flow)]}`,
    }));
  if (kind === "buffer-tokens") return recordsOf("Buffer").map((record) => ({ value: record.id, label: tokenLabel(record.id) }));
  if (kind === "compatible-quoters") return compatibleQuoterOptions();
  return [];
}

export function mintableTokenAddresses() {
  return [state.fixtures.assetToken, state.fixtures.onReToken]
    .filter((address) => address && isAddress(address))
    .map((address) => getAddress(address));
}

function vaultOptions(kind) {
  return recordsOf("Vault").filter((record) => enumValue(record.value.kind) === kind).map((record) => ({ value: record.id, label: entityLabel("Vault", record.id) }));
}

function compatibleQuoterOptions() {
  const form = $("#create-offer-form");
  const flow = Number(form.elements.flow.value || 0);
  const tokenIn = form.elements.tokenIn.value;
  const tokenOut = form.elements.tokenOut.value;
  const rfqStates = new Map(recordsOf("Prop RFQ").map((record) => [String(record.id).toLowerCase(), record.value]));
  return recordsOf("Quoter").filter((record) => {
    if (record.value.disabled) return false;
    const kind = enumValue(record.value.kind);
    if (flow === 0 || flow === 2) return kind === 0;
    if (flow !== 1 || ![1, 2].includes(kind)) return false;
    if (kind === 1) return true;
    const rfqState = rfqStates.get(String(record.id).toLowerCase());
    if (!rfqState || !tokenIn || !tokenOut) return false;
    const pair = new Set([tokenIn.toLowerCase(), tokenOut.toLowerCase()]);
    return pair.has(rfqState.assetToken.toLowerCase()) && pair.has(rfqState.onReToken.toLowerCase());
  }).map((record) => ({ value: record.id, label: entityLabel("Quoter", record.id) }));
}
