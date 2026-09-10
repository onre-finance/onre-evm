import { parseUnits } from "viem";
import { APR_SCALE, erc20MetadataAbi, OFFER_FLOWS, managedTokenArtifact, PRICE_DECIMALS, QUOTER_KINDS, VAULT_KINDS, ZERO_BYTES32 } from "./config.js";
import { readDiamond, writeBossDiamond, writeBossToken } from "./chain.js";
import { hydrateTokenMetadata, recordById, recordsOf } from "./data.js";
import { entityLabel, tokenLabel, tokenMeta } from "./model.js";
import { ensurePermissionlessTokenApprovals } from "./permissionless.js";
import { state, storeTrackedTokens } from "./state.js";
import { formatBps, formatPercentScaled, formatTokenAmount, formatUsdPrice, requiredAddress, requiredValue, short } from "./utils.js";

export async function registerManagedToken(form) {
  const token = requiredAddress(form.elements.managedToken.value, "Token");
  await writeBossToken(token, managedTokenArtifact.abi, "grantMintAndBurnRoles", [state.diamondAddress]);
  await ensurePermissionlessTokenApprovals([token]);
  await writeBossDiamond("registerManagedToken", [token]);
  state.trackedTokens.add(token);
  storeTrackedTokens();
  return `${tokenLabel(token)} registered as a managed token.`;
}

export async function trackToken(form) {
  const token = requiredAddress(form.elements.token.value, "Token");
  state.trackedTokens.add(token);
  storeTrackedTokens();
  await hydrateTokenMetadata();
  form.reset();
  return `${tokenLabel(token)} is now displayed in this browser.`;
}

export async function createPricer(form) {
  const token = requiredAddress(form.elements.managedToken.value, "Managed token");
  const result = await writeBossDiamond("createPricer", [token, Number(form.elements.denomination.value)]);
  return `Created ${tokenLabel(token)} / USD pricer (${short(result.simulatedResult)}).`;
}

export async function addPricingVector(form) {
  const pricerId = requiredValue(form.elements.pricerId.value, "Pricer");
  const baseTime = dateTimeSeconds(form.elements.baseTime.value, "Curve base time");
  const startTime = dateTimeSeconds(form.elements.startTime.value, "Activation time");
  if (baseTime >= startTime) throw new Error("Curve base time must be earlier than activation time.");
  const currentTime = (await state.publicClient.getBlock()).timestamp;
  if (startTime <= currentTime) throw new Error("Activation time must be later than the current chain time.");
  const basePrice = parseUnits(requiredValue(form.elements.basePrice.value, "Base price"), PRICE_DECIMALS);
  const apr = BigInt(Math.round(Number(form.elements.apr.value) * APR_SCALE / 100));
  const priceFixDuration = BigInt(form.elements.priceFixDuration.value);
  await writeBossDiamond("addPricingVector", [pricerId, { startTime, baseTime, basePrice, apr, priceFixDuration }]);
  return `Added ${formatUsdPrice(basePrice)} vector with ${formatPercentScaled(apr)} APR.`;
}

function dateTimeSeconds(value, label) {
  const milliseconds = Date.parse(`${value}Z`);
  if (!Number.isFinite(milliseconds) || milliseconds <= 0) throw new Error(`${label} must be a valid date and time.`);
  return BigInt(Math.floor(milliseconds / 1000));
}

export async function createQuoter(form) {
  const kind = Number(form.elements.kind.value);
  const instanceId = BigInt(requiredValue(form.elements.instanceId.value, "Instance number"));
  const result = await writeBossDiamond("createQuoter", [kind, instanceId]);
  return `Created ${QUOTER_KINDS[kind]} #${instanceId} (${short(result.simulatedResult)}).`;
}

export async function configurePropRfq(form) {
  const quoterId = requiredValue(form.elements.quoterId.value, "RFQ quoter");
  const assetToken = requiredAddress(form.elements.assetToken.value, "Asset token");
  const managedToken = requiredAddress(form.elements.managedToken.value, "Managed token");
  await writeBossDiamond("configurePropRfq", [quoterId, assetToken, managedToken, {
    epochDurationSeconds: BigInt(Math.round(Number(form.elements.epochHours.value) * 3600)),
    curveExponentScaled: Number(form.elements.curveExponent.value),
    cadenceThreshold: Number(form.elements.cadenceThreshold.value),
    cadenceWaveScaled: Number(form.elements.cadenceWave.value),
    wallSensitivityScaled: Number(form.elements.wallSensitivity.value),
    curvePegHaircutBps: Number(form.elements.haircutBps.value),
  }]);
  return `Configured ${entityLabel("Quoter", quoterId)} for ${tokenLabel(assetToken)} ↔ ${tokenLabel(managedToken)}.`;
}

export async function createVault(form) {
  const kind = Number(form.elements.kind.value);
  const instanceId = BigInt(requiredValue(form.elements.instanceId.value, "Instance number"));
  const destination = requiredAddress(form.elements.destination.value, "Withdrawal destination");
  const refillTargetBps = Math.round(Number(form.elements.refillTarget.value) * 100);
  const result = await writeBossDiamond("createConfigurableVault", [kind, instanceId, destination, refillTargetBps]);
  return `Created ${VAULT_KINDS[kind]} vault #${instanceId} (${short(result.simulatedResult)}).`;
}

export async function manageVaultBalance(form) {
  const vaultId = requiredValue(form.elements.vaultId.value, "Vault");
  const token = requiredAddress(form.elements.token.value, "Token");
  const meta = tokenMeta(token);
  if (meta.decimals === undefined) throw new Error("Token decimals could not be read.");
  const amount = parseUnits(requiredValue(form.elements.amount.value, "Amount"), meta.decimals);
  if (form.elements.action.value === "deposit") {
    await writeBossToken(token, erc20MetadataAbi, "approve", [state.diamondAddress, amount]);
    await writeBossDiamond("depositConfigurableVault", [vaultId, token, amount]);
    return `Deposited ${formatTokenAmount(amount, meta.decimals)} ${meta.symbol} into ${entityLabel("Vault", vaultId)}.`;
  }
  await writeBossDiamond("withdrawConfigurableVault", [vaultId, token, amount]);
  return `Withdrew ${formatTokenAmount(amount, meta.decimals)} ${meta.symbol} from ${entityLabel("Vault", vaultId)}.`;
}

export async function createFeeConfig(form) {
  const instanceId = BigInt(requiredValue(form.elements.instanceId.value, "Instance number"));
  const basisPoints = Math.round(Number(form.elements.feePercent.value) * 100);
  const minimumFeeAmount = BigInt(requiredValue(form.elements.minimumFee.value, "Minimum fee"));
  const feeVaultId = requiredValue(form.elements.feeVaultId.value, "Fee vault");
  const result = await writeBossDiamond("createFeeConfig", [instanceId, basisPoints, minimumFeeAmount, feeVaultId]);
  return `Created fee config #${instanceId} at ${formatBps(basisPoints)} (${short(result.simulatedResult)}).`;
}

export async function createOffer(form) {
  const tokenIn = requiredAddress(form.elements.tokenIn.value, "Input token");
  const tokenOut = requiredAddress(form.elements.tokenOut.value, "Output token");
  if (tokenIn === tokenOut) throw new Error("Input and output tokens must differ.");
  const flow = Number(form.elements.flow.value);
  const quoterId = requiredValue(form.elements.quoterId.value, "Compatible quoter");
  const feeConfigId = requiredValue(form.elements.feeConfigId.value, "Fee configuration");
  const proceedsVaultId = requiredValue(form.elements.proceedsVaultId.value, "Proceeds vault");
  const liquidityVaultId = form.elements.liquidityVaultId.value || ZERO_BYTES32;
  const managedToken = [tokenIn, tokenOut].find((token) => recordsOf("Managed token").some((record) => String(record.id).toLowerCase() === token.toLowerCase()));
  const pricer = managedToken && recordsOf("Pricer").find((record) => record.value.managedToken.toLowerCase() === managedToken.toLowerCase());
  if (!pricer) throw new Error("This pair has no USD pricer for its Managed token.");
  if (flow === 1) await ensurePermissionlessTokenApprovals([tokenIn, tokenOut]);
  const result = await writeBossDiamond("makeOfferConfig", [{ tokenIn, tokenOut, flow, quoterId, feeConfigId, proceedsVaultId, liquidityVaultId }]);
  return `Created ${tokenLabel(tokenIn)} → ${tokenLabel(tokenOut)} ${OFFER_FLOWS[flow]} offer (${short(result.simulatedResult)}).`;
}

export async function initializeBuffer(form) {
  const managedToken = requiredAddress(form.elements.managedToken.value, "Managed token");
  const pricer = recordsOf("Pricer").find((record) => record.value.managedToken.toLowerCase() === managedToken.toLowerCase());
  if (!pricer) throw new Error("Create this token's USD pricer and active pricing vector before initializing its Buffer.");
  await readDiamond("currentPrice", [pricer.id]);
  await writeBossDiamond("initializeBuffer", [managedToken]);
  return `Initialized the ${tokenLabel(managedToken)} Buffer and its three derived vaults.`;
}

export async function configureBuffer(form) {
  const managedToken = requiredAddress(form.elements.managedToken.value, "Managed token");
  const reserveDestination = requiredAddress(form.elements.reserveDestination.value, "Reserve withdrawal destination");
  const managementFeeDestination = requiredAddress(form.elements.managementFeeDestination.value, "Management-fee withdrawal destination");
  const performanceFeeDestination = requiredAddress(form.elements.performanceFeeDestination.value, "Performance-fee withdrawal destination");
  const grossAprPercent = Number(form.elements.grossApr.value);
  const managementFeePercent = Number(form.elements.managementFee.value);
  const performanceFeePercent = Number(form.elements.performanceFee.value);
  for (const [label, value] of [
    ["Gross APR", grossAprPercent],
    ["Management fee", managementFeePercent],
    ["Performance fee", performanceFeePercent],
  ]) {
    if (!Number.isFinite(value) || value < 0 || value > 100) throw new Error(`${label} must be between 0% and 100%.`);
  }

  const buffer = recordById("Buffer", managedToken)?.value;
  if (!buffer) throw new Error("Initialize this Buffer first.");
  const pricer = recordsOf("Pricer").find((record) => record.value.managedToken.toLowerCase() === managedToken.toLowerCase());
  if (!pricer) throw new Error("Create this token's USD pricer and active pricing vector before activating its Buffer.");
  await readDiamond("currentPrice", [pricer.id]);

  const grossApr = Math.round(grossAprPercent * APR_SCALE / 100);
  const managementFee = Math.round(managementFeePercent * 100);
  const performanceFee = Math.round(performanceFeePercent * 100);

  await updateBufferVaultDestination(buffer.reserveVaultId, reserveDestination);
  await updateBufferVaultDestination(buffer.managementFeeVaultId, managementFeeDestination);
  await updateBufferVaultDestination(buffer.performanceFeeVaultId, performanceFeeDestination);

  const currentController = await state.publicClient.readContract({
    address: managedToken,
    abi: managedTokenArtifact.abi,
    functionName: "bufferController",
  });
  if (currentController.toLowerCase() !== state.diamondAddress.toLowerCase()) {
    await writeBossToken(managedToken, managedTokenArtifact.abi, "setBufferController", [state.diamondAddress]);
  }

  if (Number(buffer.grossApr) !== grossApr) await writeBossDiamond("setBufferGrossApr", [managedToken, grossApr]);
  if (
    Number(buffer.managementFeeBasisPoints) !== managementFee
    || Number(buffer.performanceFeeBasisPoints) !== performanceFee
    || buffer.performanceFeeHighWatermarkEnabled !== form.elements.highWatermark.checked
  ) {
    await writeBossDiamond("setBufferFeeConfig", [managedToken, managementFee, performanceFee, form.elements.highWatermark.checked]);
  }
  return `Activated ${tokenLabel(managedToken)} Buffer with its Diamond controller, vault destinations, and fee configuration.`;
}

async function updateBufferVaultDestination(vaultId, withdrawalDestination) {
  const vault = await readDiamond("getConfigurableVault", [vaultId]);
  if (vault.withdrawalDestination.toLowerCase() === withdrawalDestination.toLowerCase()) return;
  await writeBossDiamond("updateConfigurableVault", [vaultId, withdrawalDestination, Number(vault.refillTargetBps)]);
}
