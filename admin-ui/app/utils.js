import { formatUnits, getAddress, isAddress, zeroAddress } from "viem";
import { APR_SCALE, BASIS_POINTS, PRICE_DECIMALS } from "./config.js";

export function stringify(value, pretty = true) {
  return JSON.stringify(value, (_, item) => typeof item === "bigint" ? item.toString() : item, pretty ? 2 : 0);
}

export function friendlyError(error) {
  return error?.shortMessage || error?.details || error?.message || String(error);
}

export function short(value) {
  if (!value) return "—";
  const text = String(value);
  return text.length > 15 ? `${text.slice(0, 8)}…${text.slice(-6)}` : text;
}

export function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

export function enumValue(value) {
  return Number(value ?? 0);
}

export function formatUsdPrice(value) {
  return `$${formatUnits(BigInt(value), PRICE_DECIMALS)}`;
}

export function formatPercentScaled(value) {
  const percent = Number(value) * 100 / APR_SCALE;
  return `${percent.toLocaleString(undefined, { maximumFractionDigits: 4 })}%`;
}

export function formatBps(value) {
  const percent = Number(value) * 100 / BASIS_POINTS;
  return `${percent.toLocaleString(undefined, { maximumFractionDigits: 4 })}%`;
}

export function formatDuration(seconds) {
  const value = Number(seconds);
  if (value % 86_400 === 0) return `${value / 86_400} day${value === 86_400 ? "" : "s"}`;
  if (value % 3_600 === 0) return `${value / 3_600} hour${value === 3_600 ? "" : "s"}`;
  return `${value.toLocaleString()} seconds`;
}

export function formatDate(timestamp) {
  const seconds = Number(timestamp);
  if (!seconds) return "Never";
  return new Date(seconds * 1000).toISOString().replace("T", " ").replace(".000Z", " UTC");
}

export function formatTokenAmount(value, decimals) {
  if (decimals === undefined) return `${value} raw units`;
  return Number(formatUnits(BigInt(value), decimals)).toLocaleString(undefined, { maximumFractionDigits: Math.min(decimals, 6) });
}

export function requiredValue(value, label) {
  const next = String(value || "").trim();
  if (!next) throw new Error(`${label} is required. Create the dependency first if the list is empty.`);
  return next;
}

export function requiredAddress(value, label) {
  const next = requiredValue(value, label);
  if (!isAddress(next)) throw new Error(`${label} must be a valid address.`);
  return getAddress(next);
}

export function utcDateTimeValue(date) {
  return date.toISOString().slice(0, 16);
}

export function normalizeBytecode(value) {
  return value.startsWith("0x") ? value : `0x${value}`;
}

export function parseAbiInput(input, raw) {
  if (input.type.endsWith("]")) {
    const values = JSON.parse(raw);
    const baseType = input.type.replace(/\[[^\]]*\]$/, "");
    return values.map((value) => parseAbiValue({ ...input, type: baseType }, value));
  }
  if (input.type === "tuple") return parseAbiValue(input, JSON.parse(raw));
  return parseAbiValue(input, raw);
}

function parseAbiValue(input, value) {
  if (input.type === "tuple") {
    const components = input.components || [];
    if (Array.isArray(value)) return components.map((component, index) => parseAbiValue(component, value[index]));
    return Object.fromEntries(components.map((component) => [component.name, parseAbiValue(component, value[component.name])]));
  }
  if (input.type.endsWith("]")) {
    const baseType = input.type.replace(/\[[^\]]*\]$/, "");
    return value.map((entry) => parseAbiValue({ ...input, type: baseType }, entry));
  }
  if (input.type === "bool") return typeof value === "boolean" ? value : String(value).toLowerCase() === "true";
  if (/^u?int\d*$/.test(input.type)) return BigInt(value);
  if (input.type === "address") return getAddress(value);
  return value;
}

export function exampleValue(input) {
  if (input.type.endsWith("]")) return [];
  if (input.type === "tuple") return Object.fromEntries((input.components || []).map((component) => [component.name, exampleValue(component)]));
  if (input.type === "address") return zeroAddress;
  if (input.type === "bool") return false;
  if (/^u?int\d*$/.test(input.type)) return "0";
  if (input.type.startsWith("bytes")) return input.type === "bytes" ? "0x" : `0x${"00".repeat(Number(input.type.slice(5) || 32))}`;
  return "";
}
