import { defineChain, getAddress } from "viem";
import diamondAbi from "../../src/generated/abi.json";
import deployments from "../../gemforge.deployments.json";
import onReTokenArtifact from "../../out/OnReToken.sol/OnReToken.json";
import proxyArtifact from "../../out/ERC1967Proxy.sol/ERC1967Proxy.json";
import localAssetArtifact from "../../out/LocalAssetToken.sol/LocalAssetToken.json";
import localFixtures from "../local-deployment.json";

export { diamondAbi, localAssetArtifact, localFixtures, onReTokenArtifact, proxyArtifact };

export const DEFAULT_PERMISSIONLESS_ACCOUNT = getAddress("0x70997970C51812dc3A010C7d01b50e0d17dc79C8");
export const MAX_UINT256 = (1n << 256n) - 1n;
export const ZERO_BYTES32 = `0x${"00".repeat(32)}`;
export const PRICE_DECIMALS = 9;
export const APR_SCALE = 1_000_000;
export const BASIS_POINTS = 10_000;
export const PRICING_DENOMINATIONS = ["USD"];
export const QUOTER_KINDS = ["NAV", "NAV permissionless", "Proprietary RFQ"];
export const VAULT_KINDS = ["Fee", "Proceeds", "Liquidity"];
export const OFFER_FLOWS = ["Permissioned", "Permissionless", "Worker"];
export const OFFER_DIRECTIONS = ["Asset → OnRe", "OnRe → asset"];

export const erc20MetadataAbi = [
  { type: "function", name: "name", stateMutability: "view", inputs: [], outputs: [{ type: "string" }] },
  { type: "function", name: "symbol", stateMutability: "view", inputs: [], outputs: [{ type: "string" }] },
  { type: "function", name: "decimals", stateMutability: "view", inputs: [], outputs: [{ type: "uint8" }] },
  { type: "function", name: "balanceOf", stateMutability: "view", inputs: [{ name: "account", type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "allowance", stateMutability: "view", inputs: [{ name: "owner", type: "address" }, { name: "spender", type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "approve", stateMutability: "nonpayable", inputs: [{ name: "spender", type: "address" }, { name: "amount", type: "uint256" }], outputs: [{ type: "bool" }] },
];

export const anvil = defineChain({
  id: 31337,
  name: "Anvil",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: { default: { http: ["http://127.0.0.1:8545"] } },
});

export const getterByEvent = {
  OnReTokenRegistered: ["OnRe token", "onReToken", "getOnReTokenConfig"],
  PricerCreated: ["Pricer", "pricerId", "getPricer"],
  QuoterCreated: ["Quoter", "quoterId", "getQuoter"],
  PropRfqConfigured: ["Prop RFQ", "quoterId", "getPropRfqState"],
  FeeConfigCreated: ["Fee config", "feeConfigId", "getFeeConfig"],
  ConfigurableVaultCreated: ["Vault", "vaultId", "getConfigurableVault"],
  OfferConfigCreated: ["Offer", "offerConfigId", "getOfferConfig"],
  FulfillmentRequested: ["Fulfillment request", "fulfillmentRequestId", "getFulfillmentRequest"],
};

export const advancedMethods = new Set(["diamondCut", "onBeforeSupplyChange", "renounceRole"]);
export const localDeployment = deployments.local?.contracts?.find((entry) => entry.name === "DiamondProxy")?.onChain?.address;
