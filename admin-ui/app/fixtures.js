import { localAssetArtifact, managedTokenArtifact } from "./config.js";
import { deployContract, requireBossWallet, requireDiamond, requirePermissionlessWallet, writeBossDiamond } from "./chain.js";
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
  const managedTokenImplementation = await deployContract(managedTokenArtifact, []);
  const { simulatedResult: managedToken } = await writeBossDiamond("deployManagedToken", [
    managedTokenImplementation,
    "Mock ONyc",
    "ONyc",
    9,
    state.bossAccount,
    state.bossAccount,
    [state.bossAccount],
    [],
  ]);
  const assetToken = await deployContract(localAssetArtifact, ["Mock USDC", "USDC", 6]);
  replaceFixtures({ managedTokenImplementation, managedToken, assetToken });
  await ensurePermissionlessTokenApprovals([managedToken, assetToken]);
  await hydrateTokenMetadata();
  renderFixtures();
  log(`Local fixtures deployed through the Diamond factory: managed token ${managedToken}, asset ${assetToken}`);
  return state.fixtures;
}

export function renderFixtures() {
  const entries = [
    ["Managed token implementation", "Implementation contract", state.fixtures.managedTokenImplementation],
    ["Managed token", state.fixtures.managedToken && tokenLabel(state.fixtures.managedToken), state.fixtures.managedToken],
    ["Asset token", state.fixtures.assetToken && tokenLabel(state.fixtures.assetToken), state.fixtures.assetToken],
  ].filter(([, , value]) => value);
  $("#fixture-grid").innerHTML = entries.length
    ? entries.map(([label, title, value]) => `<div class="entity-card"><p class="eyebrow">${label}</p><h4>${escapeHtml(title)}</h4><details class="technical"><summary>Contract address</summary><code>${escapeHtml(value)}</code></details></div>`).join("")
    : '<p class="muted">No local fixture addresses are saved in this browser.</p>';
}
