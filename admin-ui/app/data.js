import { decodeEventLog, getAddress, isAddress } from "viem";
import { diamondAbi, erc20MetadataAbi, getterByEvent } from "./config.js";
import { readDiamond } from "./chain.js";
import { state } from "./state.js";
import { friendlyError } from "./utils.js";

export async function scanEventsAndRecords() {
  const logs = await state.publicClient.getLogs({ address: state.diamondAddress, fromBlock: 0n, toBlock: "latest" });
  state.latestEvents = logs.flatMap((entry) => {
    try {
      const decoded = decodeEventLog({ abi: diamondAbi, data: entry.data, topics: entry.topics, strict: false });
      return [{ ...decoded, blockNumber: entry.blockNumber, transactionHash: entry.transactionHash, logIndex: entry.logIndex }];
    } catch {
      return [];
    }
  });

  const unique = new Map();
  for (const event of state.latestEvents) {
    const mapping = getterByEvent[event.eventName];
    if (!mapping) continue;
    const [type, idField, getter] = mapping;
    const id = event.args[idField];
    if (id === undefined) continue;
    unique.set(`${type}:${String(id).toLowerCase()}`, {
      type,
      id,
      getter,
      sourceEvent: event.eventName,
      eventArgs: event.args,
      blockNumber: event.blockNumber,
    });
  }

  state.discoveredRecords = await Promise.all([...unique.values()].map(async (record) => {
    try {
      return { ...record, value: await readDiamond(record.getter, [record.id]) };
    } catch (error) {
      return { ...record, error: friendlyError(error) };
    }
  }));
  state.discoveredRecords.sort((a, b) => a.type.localeCompare(b.type));
}

export async function hydrateDomainData() {
  await hydrateTokenMetadata();
  await hydrateReadableState();
}

export async function hydrateTokenMetadata() {
  if (!state.publicClient) return;
  const entries = await Promise.all(knownTokenAddresses().map(async (address) => {
    try {
      const [name, symbol, decimals] = await Promise.all([
        state.publicClient.readContract({ address, abi: erc20MetadataAbi, functionName: "name" }),
        state.publicClient.readContract({ address, abi: erc20MetadataAbi, functionName: "symbol" }),
        state.publicClient.readContract({ address, abi: erc20MetadataAbi, functionName: "decimals" }),
      ]);
      return [address.toLowerCase(), { address, name, symbol, decimals: Number(decimals) }];
    } catch (error) {
      console.warn(`Could not load token metadata for ${address}`, friendlyError(error));
      return [address.toLowerCase(), { address, name: "Unknown token", symbol: "TOKEN", decimals: undefined }];
    }
  }));
  state.tokenMetadata = new Map(entries);
}

async function hydrateReadableState() {
  if (!state.publicClient || !state.diamondAddress) return;
  await Promise.all(recordsOf("Pricer").map(async (record) => {
    try {
      record.currentPrice = await readDiamond("currentPrice", [record.id]);
    } catch {
      record.currentPrice = undefined;
    }
  }));
  const tokens = knownTokenAddresses();
  await Promise.all(recordsOf("Vault").flatMap((record) => tokens.map(async (token) => {
    record.balances ||= {};
    try {
      record.balances[token.toLowerCase()] = await readDiamond("configurableVaultBalance", [record.id, token]);
    } catch {
      record.balances[token.toLowerCase()] = 0n;
    }
  })));
}

export function knownTokenAddresses() {
  const values = new Set([...state.trackedTokens, state.fixtures.onReToken, state.fixtures.assetToken].filter(Boolean));
  for (const record of state.discoveredRecords) {
    if (record.type === "OnRe token") values.add(String(record.id));
    for (const field of ["onReToken", "assetToken", "tokenIn", "tokenOut"]) {
      const value = record.value?.[field] || record.eventArgs?.[field];
      if (value && isAddress(value)) values.add(getAddress(value));
    }
  }
  return [...values].filter((value) => value && isAddress(value)).map((value) => getAddress(value));
}

export function recordsOf(type) {
  return state.discoveredRecords
    .filter((record) => record.type === type && !record.error && record.value?.exists !== false)
    .sort((a, b) => Number(b.blockNumber || 0n) - Number(a.blockNumber || 0n));
}

export function recordById(type, id) {
  if (!id) return undefined;
  return recordsOf(type).find((record) => String(record.id).toLowerCase() === String(id).toLowerCase());
}
