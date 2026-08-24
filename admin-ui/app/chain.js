import { createPublicClient, createWalletClient, custom, getAddress, http, isAddress, zeroAddress } from "viem";
import { anvil, diamondAbi } from "./config.js";
import { loadStorageScope, state } from "./state.js";
import { log } from "./ui.js";
import { normalizeBytecode, short } from "./utils.js";

const ANVIL_ACTOR_BALANCE = "0x3635c9adc5dea00000";
const announcedWalletProviders = new Map();

window.addEventListener("eip6963:announceProvider", (event) => {
  const detail = event.detail;
  if (detail?.info?.uuid && detail?.provider?.request) announcedWalletProviders.set(detail.info.uuid, detail);
});
window.dispatchEvent(new Event("eip6963:requestProvider"));

export function configureConnection(rpcUrl, diamondAddress) {
  if (!rpcUrl) throw new Error("RPC URL is required.");
  if (diamondAddress && !isAddress(diamondAddress)) throw new Error("Diamond address is invalid.");
  const nextDiamondAddress = diamondAddress ? getAddress(diamondAddress) : "";
  const changedDiamond = state.diamondAddress.toLowerCase() !== nextDiamondAddress.toLowerCase();
  const changedRpc = state.rpcUrl !== rpcUrl;
  state.rpcUrl = rpcUrl;
  state.diamondAddress = nextDiamondAddress;
  if (changedDiamond) loadStorageScope(nextDiamondAddress);
  if (changedRpc && !changedDiamond) {
    state.bossWalletClient = undefined;
    state.bossAccount = undefined;
    state.permissionlessWalletClient = undefined;
    state.permissionlessAccount = undefined;
  }
  localStorage.setItem("onre.rpcUrl", state.rpcUrl);
  if (state.diamondAddress) localStorage.setItem("onre.diamondAddress", state.diamondAddress);
  state.publicClient = createPublicClient({ chain: anvil, transport: http(state.rpcUrl) });
}

export async function connectBrowserWallet() {
  const provider = await findMetaMaskProvider();
  state.userWalletProvider = provider;
  await ensureBrowserWalletChain(provider);
  const accounts = await provider.request({ method: "eth_requestAccounts" });
  setBrowserWalletAccount(accounts[0]);
  if (state.publicClient) {
    await state.publicClient.request({
      method: "anvil_setBalance",
      params: [state.userAccount, ANVIL_ACTOR_BALANCE],
    });
  }
  log(`Connected MetaMask wallet ${state.userAccount}`);
  return provider;
}

export function setBrowserWalletAccount(account) {
  state.userAccount = account ? getAddress(account) : undefined;
  state.userWalletClient = state.userAccount && state.userWalletProvider
    ? createWalletClient({ account: state.userAccount, chain: anvil, transport: custom(state.userWalletProvider) })
    : undefined;
}

async function findMetaMaskProvider() {
  window.dispatchEvent(new Event("eip6963:requestProvider"));
  await new Promise((resolve) => setTimeout(resolve, 100));

  const announcedProviders = [...announcedWalletProviders.values()];
  const announcedMetaMask = announcedProviders.find(({ info }) => info.rdns?.toLowerCase() === "io.metamask")
    || announcedProviders.find(({ provider }) => provider.isMetaMask && !provider.isBraveWallet);
  if (announcedMetaMask) return announcedMetaMask.provider;

  const legacyProviders = window.ethereum?.providers || [window.ethereum];
  const legacyMetaMask = legacyProviders.find((provider) => provider?.isMetaMask && !provider.isBraveWallet);
  if (legacyMetaMask) return legacyMetaMask;

  throw new Error("MetaMask was not detected. Install or enable the MetaMask browser extension.");
}

async function ensureBrowserWalletChain(provider) {
  const chainId = "0x7a69";
  try {
    await provider.request({ method: "wallet_switchEthereumChain", params: [{ chainId }] });
  } catch (error) {
    if (error.code !== 4902) throw error;
    await provider.request({
      method: "wallet_addEthereumChain",
      params: [{ chainId, chainName: "Anvil", nativeCurrency: anvil.nativeCurrency, rpcUrls: [state.rpcUrl] }],
    });
  }
}

export async function connectAnvilActors(defaultPermissionlessAccount) {
  requireDiamond();

  const boss = getAddress(await readDiamond("boss", []));
  await impersonateAnvilAccount(boss);
  state.bossAccount = boss;
  state.bossWalletClient = createWalletClient({ account: boss, chain: anvil, transport: http(state.rpcUrl) });
  log(`Prepared contract boss ${boss} through Anvil.`);

  let permissionlessAccount = getAddress(await readDiamond("permissionlessSettlementAccount", []));
  if (permissionlessAccount === zeroAddress) {
    if (!defaultPermissionlessAccount || !isAddress(defaultPermissionlessAccount)) {
      throw new Error("Enter a valid permissionless settlement account.");
    }
    permissionlessAccount = getAddress(defaultPermissionlessAccount);
    if (permissionlessAccount === state.diamondAddress) {
      throw new Error("The Diamond cannot be the permissionless settlement account.");
    }
    if (permissionlessAccount === boss) {
      throw new Error("Use a permissionless settlement account distinct from the boss.");
    }
    if (state.userAccount && permissionlessAccount === state.userAccount) {
      throw new Error("Use a permissionless settlement account distinct from the connected user wallet.");
    }
    await writeBossDiamond("setPermissionlessSettlementAccount", [permissionlessAccount]);
  }
  if (state.userAccount && permissionlessAccount.toLowerCase() === state.userAccount.toLowerCase()) {
    throw new Error("The configured permissionless account must differ from the connected user wallet.");
  }

  await impersonateAnvilAccount(permissionlessAccount);
  state.permissionlessAccount = permissionlessAccount;
  state.permissionlessWalletClient = createWalletClient({
    account: permissionlessAccount,
    chain: anvil,
    transport: http(state.rpcUrl),
  });
  log(`Prepared permissionless settlement account ${permissionlessAccount} through Anvil.`);
  return { boss, permissionlessAccount };
}

async function impersonateAnvilAccount(account) {
  await state.publicClient.request({ method: "anvil_impersonateAccount", params: [account] });
  await state.publicClient.request({ method: "anvil_setBalance", params: [account, ANVIL_ACTOR_BALANCE] });
}

export async function readDiamond(functionName, args) {
  requireDiamond();
  return state.publicClient.readContract({ address: state.diamondAddress, abi: diamondAbi, functionName, args });
}

export async function writeBossDiamond(functionName, args) {
  requireBossWallet();
  requireDiamond();
  return writeContract(state.bossWalletClient, state.bossAccount, state.diamondAddress, diamondAbi, functionName, args);
}

export async function writeUserDiamond(functionName, args) {
  requireUserWallet();
  requireDiamond();
  return writeContract(state.userWalletClient, state.userAccount, state.diamondAddress, diamondAbi, functionName, args);
}

export async function writeBossToken(address, abi, functionName, args) {
  requireBossWallet();
  return writeTokenContract(state.bossWalletClient, state.bossAccount, address, abi, functionName, args);
}

export async function writeUserToken(address, abi, functionName, args) {
  requireUserWallet();
  return writeTokenContract(state.userWalletClient, state.userAccount, address, abi, functionName, args);
}

export async function writePermissionlessToken(address, abi, functionName, args) {
  requirePermissionlessWallet();
  return writeTokenContract(
    state.permissionlessWalletClient,
    state.permissionlessAccount,
    address,
    abi,
    functionName,
    args,
  );
}

async function writeContract(walletClient, account, address, abi, functionName, args) {
  const simulation = await state.publicClient.simulateContract({ account, address, abi, functionName, args });
  const hash = await walletClient.writeContract(simulation.request);
  log(`${functionName}: ${hash}`);
  const receipt = await state.publicClient.waitForTransactionReceipt({ hash });
  log(`${functionName}: confirmed in block ${receipt.blockNumber}`);
  return { simulatedResult: simulation.result, hash, blockNumber: receipt.blockNumber, status: receipt.status };
}

async function writeTokenContract(walletClient, account, address, abi, functionName, args) {
  const simulation = await state.publicClient.simulateContract({ account, address, abi, functionName, args });
  if (simulation.result === false) throw new Error(`${functionName} on ${short(address)} returned false.`);
  const hash = await walletClient.writeContract(simulation.request);
  log(`${functionName} on ${short(address)} from ${short(account)}: ${hash}`);
  await state.publicClient.waitForTransactionReceipt({ hash });
  return simulation.result;
}

export async function deployContract(artifact, args) {
  requireBossWallet();
  const hash = await state.bossWalletClient.deployContract({
    account: state.bossAccount,
    abi: artifact.abi,
    bytecode: normalizeBytecode(artifact.bytecode.object),
    args,
  });
  log(`Deploying contract from boss ${short(state.bossAccount)}: ${hash}`);
  const receipt = await state.publicClient.waitForTransactionReceipt({ hash });
  if (!receipt.contractAddress) throw new Error("Deployment receipt did not contain a contract address.");
  return receipt.contractAddress;
}

export function requireUserWallet() {
  if (!state.userWalletClient || !state.userAccount) throw new Error("Connect MetaMask first.");
}

export function requireBossWallet() {
  if (!state.bossWalletClient || !state.bossAccount) throw new Error("Prepare the Anvil boss first.");
}

export function requirePermissionlessWallet() {
  if (!state.permissionlessWalletClient || !state.permissionlessAccount) {
    throw new Error("Prepare the Anvil permissionless settlement account first.");
  }
}

export function requirePublicClient() {
  if (!state.publicClient) throw new Error("Apply an RPC connection first.");
}

export function requireDiamond() {
  requirePublicClient();
  if (!state.diamondAddress || !isAddress(state.diamondAddress)) throw new Error("A valid Diamond address is required.");
}
