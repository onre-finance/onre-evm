import { encodeFunctionData } from "viem";
import { localAssetArtifact, onReTokenArtifact, proxyArtifact } from "./config.js";
import { deployContract, requireBossWallet, requireDiamond, requirePermissionlessWallet } from "./chain.js";
import { hydrateTokenMetadata } from "./data.js";
import { tokenLabel } from "./model.js";
import { ensurePermissionlessTokenApprovals } from "./permissionless.js";
import { replaceFixtures, state } from "./state.js";
import { $, log } from "./ui.js";
import { escapeHtml } from "./utils.js";

export async function deployFixtures() {
  requireBossWallet();
  requirePermissionlessWallet();
  requireDiamond();
  const onReImplementation = await deployContract(onReTokenArtifact, []);
  const initializeData = encodeFunctionData({
    abi: onReTokenArtifact.abi,
    functionName: "initialize",
    args: [{
      name: "Mock ONyc",
      symbol: "ONyc",
      admin: state.bossAccount,
      ccipAdmin: state.bossAccount,
      initialMinters: [state.bossAccount, state.diamondAddress],
      initialBurners: [state.diamondAddress],
    }],
  });
  const onReToken = await deployContract(proxyArtifact, [onReImplementation, initializeData]);
  const assetToken = await deployContract(localAssetArtifact, ["Mock USDC", "USDC", 6]);
  replaceFixtures({ onReImplementation, onReToken, assetToken });
  await ensurePermissionlessTokenApprovals([onReToken, assetToken]);
  await hydrateTokenMetadata();
  renderFixtures();
  log(`Local fixtures deployed: OnRe ${onReToken}, asset ${assetToken}`);
  return state.fixtures;
}

export function renderFixtures() {
  const entries = [
    ["OnRe token", state.fixtures.onReToken],
    ["Asset token", state.fixtures.assetToken],
  ].filter(([, value]) => value);
  $("#fixture-grid").innerHTML = entries.length
    ? entries.map(([label, value]) => `<div class="entity-card"><p class="eyebrow">${label}</p><h4>${escapeHtml(tokenLabel(value))}</h4><details class="technical"><summary>Contract address</summary><code>${escapeHtml(value)}</code></details></div>`).join("")
    : '<p class="muted">No local fixture addresses are saved in this browser.</p>';
}
