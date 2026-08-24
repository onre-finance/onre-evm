import { isAddress, zeroAddress } from "viem";
import { PRICING_DENOMINATIONS, QUOTER_KINDS, VAULT_KINDS } from "./config.js";
import { recordById, recordsOf } from "./data.js";
import { state } from "./state.js";
import { enumValue, formatBps, short } from "./utils.js";

export function tokenMeta(address) {
  if (!address || !isAddress(address)) return { address, name: "Unknown token", symbol: "TOKEN", decimals: undefined };
  return state.tokenMetadata.get(String(address).toLowerCase()) || { address, name: "Unknown token", symbol: "TOKEN", decimals: undefined };
}

export function tokenLabel(address) {
  const meta = tokenMeta(address);
  return meta.name === meta.symbol ? meta.symbol : `${meta.symbol} (${meta.name})`;
}

export function addressLabel(address) {
  if (!address || address === zeroAddress) return "Not configured";
  if (state.bossAccount && String(address).toLowerCase() === state.bossAccount.toLowerCase()) return `Boss · ${short(address)}`;
  if (state.permissionlessAccount && String(address).toLowerCase() === state.permissionlessAccount.toLowerCase()) {
    return `Permissionless · ${short(address)}`;
  }
  if (state.userAccount && String(address).toLowerCase() === state.userAccount.toLowerCase()) {
    return `Connected wallet · ${short(address)}`;
  }
  return short(address);
}

export function entityLabel(type, id) {
  const record = recordById(type, id);
  if (!record) return `Unknown ${type.toLowerCase()} · ${short(id)}`;
  const value = record.value;
  if (type === "Pricer") return `${tokenLabel(value.onReToken)} / ${PRICING_DENOMINATIONS[enumValue(value.denomination)]}`;
  if (type === "Quoter") return `${QUOTER_KINDS[enumValue(value.kind)]} #${value.instanceId}`;
  if (type === "Vault") return `${VAULT_KINDS[enumValue(value.kind)]} vault #${value.vaultId}`;
  if (type === "Fee config") return `Fee config #${value.feeConfigId} · ${formatBps(value.basisPoints)}`;
  return `${type} · ${short(id)}`;
}

export function tokenUsage(address) {
  const lower = String(address).toLowerCase();
  const uses = [];
  if (recordsOf("Pricer").some((record) => record.value.onReToken.toLowerCase() === lower)) uses.push("Pricing");
  if (recordsOf("Quoter").some((record) => {
    const rfqState = recordById("Prop RFQ", record.id)?.value;
    return rfqState && [rfqState.assetToken, rfqState.onReToken].some((token) => token.toLowerCase() === lower);
  })) uses.push("Quoting");
  if (recordsOf("Offer").some((record) => [record.value.tokenIn, record.value.tokenOut].some((token) => token.toLowerCase() === lower))) uses.push("Offers");
  return uses.join(", ");
}

export function offerOnReToken(offer) {
  return [offer.tokenIn, offer.tokenOut].find((token) => recordsOf("OnRe token").some((record) => String(record.id).toLowerCase() === token.toLowerCase()));
}

export function vaultPurpose(kind) {
  return [
    "Receives execution fees",
    "Receives non-refill offer proceeds",
    "Funds asset redemptions",
  ][kind] || "Protocol vault";
}
