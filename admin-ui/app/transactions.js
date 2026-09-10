import { parseUnits, zeroAddress } from "viem";
import { BASIS_POINTS, erc20MetadataAbi, OFFER_FLOWS, localAssetArtifact, managedTokenArtifact } from "./config.js";
import { readDiamond, requireUserWallet, writeBossToken, writeUserDiamond, writeUserToken } from "./chain.js";
import { recordById } from "./data.js";
import { entityLabel, tokenLabel, tokenMeta } from "./model.js";
import { mintableTokenAddresses } from "./selectors.js";
import { state } from "./state.js";
import { $, showGlobalError } from "./ui.js";
import { enumValue, escapeHtml, formatTokenAmount, requiredAddress, requiredValue } from "./utils.js";

export async function renderWalletBalances() {
  const container = $("#wallet-balances");
  if (!state.userAccount) {
    container.innerHTML = '<p class="muted">Connect MetaMask to view balances.</p>';
    return;
  }
  const balances = await Promise.all(mintableTokenAddresses().map(async (token) => {
    const meta = tokenMeta(token);
    try {
      const balance = await state.publicClient.readContract({ address: token, abi: erc20MetadataAbi, functionName: "balanceOf", args: [state.userAccount] });
      return `<div class="balance-row"><span>${escapeHtml(tokenLabel(token))}</span><strong>${escapeHtml(formatTokenAmount(balance, meta.decimals))} ${escapeHtml(meta.symbol)}</strong></div>`;
    } catch {
      return `<div class="balance-row"><span>${escapeHtml(tokenLabel(token))}</span><strong>Unavailable</strong></div>`;
    }
  }));
  container.innerHTML = balances.length ? balances.join("") : '<p class="muted">No local mock tokens are configured.</p>';
}

export function renderTakeOfferSummary() {
  const form = $("#take-offer-form");
  const record = recordById("Offer", form.elements.offerConfigId.value);
  const summary = $("#take-offer-summary");
  const approval = $("#permissioned-approval");
  $("#preview-offer").disabled = !record;
  form.querySelector('button[type="submit"]').disabled = !record;
  if (!record) {
    summary.querySelector("strong").textContent = "Create an executable offer first";
    summary.querySelector("small").textContent = "The selected offer's token pair, flow, fee policy, and quote appear here.";
    approval.classList.add("hidden");
    return;
  }
  const offer = record.value;
  const flow = enumValue(offer.flow);
  summary.querySelector("strong").textContent = `${tokenLabel(offer.tokenIn)} → ${tokenLabel(offer.tokenOut)}`;
  summary.querySelector("small").textContent = `${OFFER_FLOWS[flow]} · ${entityLabel("Quoter", offer.quoterId)} · ${entityLabel("Fee config", offer.feeConfigId)}`;
  approval.classList.toggle("hidden", flow !== 0);
}

export function clearTakeOfferPreview() {
  state.latestTakePreview = undefined;
  $("#take-offer-preview").className = "quote-preview empty-state";
  $("#take-offer-preview").textContent = "Preview the current amount before sending.";
}

export async function previewSelectedOffer() {
  state.latestTakePreview = await loadTakeOfferPreview();
  const { offer, accounting, inputAmount, minimumAmountOut } = state.latestTakePreview;
  const inputMeta = tokenMeta(offer.tokenIn);
  const outputMeta = tokenMeta(offer.tokenOut);
  const container = $("#take-offer-preview");
  container.className = "quote-preview";
  container.innerHTML = [
    ["Gross input", `${formatTokenAmount(inputAmount, offer.tokenInDecimals)} ${inputMeta.symbol}`],
    ["Fee", `${formatTokenAmount(accounting.feeAmount, offer.tokenInDecimals)} ${inputMeta.symbol}`],
    ["Net input", `${formatTokenAmount(accounting.netInputAmount, offer.tokenInDecimals)} ${inputMeta.symbol}`],
    ["Expected output", `${formatTokenAmount(accounting.amountOut, offer.tokenOutDecimals)} ${outputMeta.symbol}`],
    ["Minimum output", `${formatTokenAmount(minimumAmountOut, offer.tokenOutDecimals)} ${outputMeta.symbol}`],
  ].map(([label, value]) => `<div class="quote-stat"><span>${escapeHtml(label)}</span><strong>${escapeHtml(value)}</strong></div>`).join("");
  return state.latestTakePreview;
}

async function loadTakeOfferPreview() {
  const form = $("#take-offer-form");
  const offerConfigId = requiredValue(form.elements.offerConfigId.value, "Offer configuration");
  const record = recordById("Offer", offerConfigId);
  if (!record || record.value.disabled) throw new Error("Select an enabled offer configuration.");
  const offer = record.value;
  if (enumValue(offer.flow) === 2) throw new Error("Worker offers must use the fulfillment-request flow.");
  const inputAmount = parseUnits(requiredValue(form.elements.grossInputAmount.value, "Gross input amount"), Number(offer.tokenInDecimals));
  const accounting = await readDiamond("previewExecution", [offerConfigId, inputAmount]);
  const slippageBps = Math.round(Number(form.elements.slippage.value) * 100);
  if (slippageBps < 0 || slippageBps > BASIS_POINTS) throw new Error("Slippage must be between 0% and 100%.");
  const minimumAmountOut = accounting.amountOut * BigInt(BASIS_POINTS - slippageBps) / BigInt(BASIS_POINTS);
  return { offerConfigId, offer, accounting, inputAmount, minimumAmountOut };
}

export async function mintMockToken(form) {
  const token = requiredAddress(form.elements.token.value, "Mock token");
  if (!mintableTokenAddresses().some((candidate) => candidate.toLowerCase() === token.toLowerCase())) {
    throw new Error("Only the configured local mock tokens can be minted here.");
  }
  const recipient = requiredAddress(form.elements.recipient.value, "Recipient");
  const meta = tokenMeta(token);
  if (meta.decimals === undefined) throw new Error("Token decimals could not be read.");
  const amount = parseUnits(requiredValue(form.elements.amount.value, "Amount"), meta.decimals);
  const abi = token.toLowerCase() === state.fixtures.managedToken?.toLowerCase() ? managedTokenArtifact.abi : localAssetArtifact.abi;
  await writeBossToken(token, abi, "mint", [recipient, amount]);
  await renderWalletBalances();
  return `Minted ${formatTokenAmount(amount, meta.decimals)} ${meta.symbol} to ${recipient}.`;
}

export async function takeSelectedOffer(form) {
  requireUserWallet();
  const preview = await previewSelectedOffer();
  const { offerConfigId, offer, inputAmount, minimumAmountOut } = preview;
  const flow = enumValue(offer.flow);
  const latestBlock = await state.publicClient.getBlock();
  const deadline = latestBlock.timestamp + BigInt(Math.round(Number(form.elements.deadlineMinutes.value) * 60));
  let approval = { user: zeroAddress, expiry: 0n };
  let signature = "0x";
  if (flow === 0) {
    approval = {
      user: state.userAccount,
      expiry: BigInt(requiredValue(form.elements.approvalExpiry.value, "Approval expiry")),
    };
    signature = requiredValue(form.elements.approvalSignature.value, "Approval signature");
  }

  if (flow === 1) {
    const permissionlessAccount = await readDiamond("permissionlessSettlementAccount", []);
    if (permissionlessAccount.toLowerCase() === state.userAccount.toLowerCase()) {
      throw new Error("The connected user wallet cannot also be the permissionless settlement account.");
    }
  }
  await writeUserToken(offer.tokenIn, erc20MetadataAbi, "approve", [state.diamondAddress, inputAmount]);

  const result = await writeUserDiamond("takeOffer", [{
    offerConfigId,
    grossInputAmount: inputAmount,
    minimumAmountOut,
    deadline,
    approval,
    signature,
  }]);
  await renderWalletBalances();
  return `Offer executed for ${formatTokenAmount(result.simulatedResult, offer.tokenOutDecimals)} ${tokenMeta(offer.tokenOut).symbol}.`;
}

export function bindTransactionControls() {
  $("#refresh-balances").addEventListener("click", () => renderWalletBalances().catch(showGlobalError));
  $("#preview-offer").addEventListener("click", () => previewSelectedOffer().catch(showGlobalError));
  const form = $("#take-offer-form");
  form.elements.offerConfigId.addEventListener("change", () => {
    renderTakeOfferSummary();
    clearTakeOfferPreview();
  });
  form.elements.grossInputAmount.addEventListener("input", clearTakeOfferPreview);
}
