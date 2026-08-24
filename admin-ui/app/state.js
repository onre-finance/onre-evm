import { getAddress, isAddress } from "viem";
import { localDeployment, localFixtures } from "./config.js";

const LOCAL_CHAIN_ID = 31337;
const bundledDiamondAddress = localDeployment || localFixtures.diamond || "";
const previousBundledDiamondAddress = localStorage.getItem("onre.bundledDiamondAddress") || "";
const storedDiamondAddress = localStorage.getItem("onre.diamondAddress") || "";
const bundledDeploymentChanged = bundledDiamondAddress
  && bundledDiamondAddress.toLowerCase() !== previousBundledDiamondAddress.toLowerCase();
const initialDiamondAddress = bundledDeploymentChanged
  ? bundledDiamondAddress
  : storedDiamondAddress || bundledDiamondAddress;
if (bundledDiamondAddress) localStorage.setItem("onre.bundledDiamondAddress", bundledDiamondAddress);

function storageKey(name, diamondAddress) {
  return `onre.${name}:${LOCAL_CHAIN_ID}:${String(diamondAddress || "unconfigured").toLowerCase()}`;
}

function localFixtureDefaults(diamondAddress) {
  if (!localFixtures.diamond || String(diamondAddress).toLowerCase() !== localFixtures.diamond.toLowerCase()) return {};
  return Object.fromEntries([
    ["onReToken", localFixtures.onReToken],
    ["assetToken", localFixtures.assetToken],
  ].filter(([, address]) => address && isAddress(address)).map(([key, address]) => [key, getAddress(address)]));
}

function normalizeFixtures(fixtures) {
  return Object.fromEntries(Object.entries(fixtures || {})
    .filter(([, address]) => address && isAddress(address))
    .map(([key, address]) => [key, getAddress(address)]));
}

function readStoredFixtures(diamondAddress) {
  try {
    const stored = localStorage.getItem(storageKey("fixtures", diamondAddress));
    return stored === null ? localFixtureDefaults(diamondAddress) : normalizeFixtures(JSON.parse(stored));
  } catch {
    return localFixtureDefaults(diamondAddress);
  }
}

function readStoredTokenAddresses(diamondAddress) {
  try {
    return new Set(JSON.parse(localStorage.getItem(storageKey("trackedTokens", diamondAddress)) || "[]")
      .filter((value) => isAddress(value))
      .map((value) => getAddress(value)));
  } catch {
    return new Set();
  }
}

export const state = {
  rpcUrl: localStorage.getItem("onre.rpcUrl") || "http://127.0.0.1:8545",
  diamondAddress: initialDiamondAddress,
  fixtures: readStoredFixtures(initialDiamondAddress),
  publicClient: undefined,
  userWalletProvider: undefined,
  userWalletClient: undefined,
  userAccount: undefined,
  bossWalletClient: undefined,
  bossAccount: undefined,
  permissionlessWalletClient: undefined,
  permissionlessAccount: undefined,
  latestEvents: [],
  discoveredRecords: [],
  tokenMetadata: new Map(),
  trackedTokens: readStoredTokenAddresses(initialDiamondAddress),
  latestTakePreview: undefined,
};

export function resetFixtures() {
  replaceFixtures({});
  localStorage.removeItem("onre.trackedTokens");
  localStorage.removeItem("onre.fixtures");
  localStorage.removeItem("onre.fixtureDiamond");
}

export function replaceFixtures(fixtures) {
  for (const address of [state.fixtures.onReToken, state.fixtures.assetToken].filter(Boolean)) {
    state.trackedTokens.delete(getAddress(address));
  }
  state.fixtures = normalizeFixtures(fixtures);
  for (const address of [state.fixtures.onReToken, state.fixtures.assetToken].filter(Boolean)) {
    state.trackedTokens.add(getAddress(address));
  }
  storeFixtures();
  storeTrackedTokens();
}

export function loadStorageScope(diamondAddress) {
  state.fixtures = readStoredFixtures(diamondAddress);
  state.trackedTokens = readStoredTokenAddresses(diamondAddress);
  state.tokenMetadata = new Map();
  state.bossWalletClient = undefined;
  state.bossAccount = undefined;
  state.permissionlessWalletClient = undefined;
  state.permissionlessAccount = undefined;
}

export function storeFixtures() {
  localStorage.setItem(storageKey("fixtures", state.diamondAddress), JSON.stringify(state.fixtures));
}

export function storeTrackedTokens() {
  localStorage.setItem(storageKey("trackedTokens", state.diamondAddress), JSON.stringify([...state.trackedTokens]));
}
