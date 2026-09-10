import { zeroAddress } from "viem";
import {
  addPricingVector,
  configureBuffer,
  configurePropRfq,
  createFeeConfig,
  createOffer,
  createPricer,
  createQuoter,
  createVault,
  initializeBuffer,
  manageVaultBalance,
  registerManagedToken,
  trackToken,
} from "./actions.js";
import { initializeAdvancedConsole } from "./advanced.js";
import { configureConnection, connectAnvilActors, connectBrowserWallet, readDiamond, setBrowserWalletAccount } from "./chain.js";
import { DEFAULT_PERMISSIONLESS_ACCOUNT } from "./config.js";
import { hydrateDomainData, knownTokenAddresses, scanEventsAndRecords } from "./data.js";
import { deployFixtures, renderFixtures } from "./fixtures.js";
import { ensurePermissionlessTokenApprovals } from "./permissionless.js";
import { renderSelectOptions } from "./selectors.js";
import { resetFixtures, state } from "./state.js";
import { renderBuffers, syncBufferForm } from "./tabs/buffer.js";
import { renderFees } from "./tabs/fees.js";
import { renderOffers, renderDerivedPricer } from "./tabs/offers.js";
import { renderOverview } from "./tabs/overview.js";
import { renderPricing } from "./tabs/pricing.js";
import { renderQuoters } from "./tabs/quoters.js";
import { renderTokens } from "./tabs/tokens.js";
import { renderVaults } from "./tabs/vaults.js";
import {
  bindTransactionControls,
  mintMockToken,
  renderTakeOfferSummary,
  renderWalletBalances,
  takeSelectedOffer,
} from "./transactions.js";
import {
  $,
  bindCopyButtons,
  bindEntityForm,
  openTab,
  showGlobalError,
  statusCard,
  withBusy,
} from "./ui.js";
import { escapeHtml, friendlyError, short, stringify, utcDateTimeValue } from "./utils.js";

const renderTransactions = () => renderWalletBalances().catch(showGlobalError);
let connectedWalletProvider;

const handleWalletAccountsChanged = ([nextAccount]) => {
  setBrowserWalletAccount(nextAccount);
  refreshStatus().catch(showGlobalError);
};

const handleWalletChainChanged = () => refreshStatus().catch(showGlobalError);

export function bootstrap() {
  $("#rpc-url").value = state.rpcUrl;
  $("#diamond-address").value = state.diamondAddress;
  $("#permissionless-account").value = DEFAULT_PERMISSIONLESS_ACCOUNT;
  initializeAdvancedConsole(refreshEverything);
  renderFixtures();
  bindActions();
  initializeFormDefaults();
  applyConnection().catch(showGlobalError);
}

function bindActions() {
  document.querySelectorAll(".tab").forEach((button) => {
    button.addEventListener("click", () => openTab(button.dataset.tab, renderTransactions));
  });
  $("#apply-connection").addEventListener("click", () => applyConnection().catch(showGlobalError));
  $("#refresh-all").addEventListener("click", () => refreshEverything().catch(showGlobalError));
  $("#connect-wallet").addEventListener("click", async () => {
    try {
      listenToWallet(await connectBrowserWallet());
      await refreshStatus();
    } catch (error) {
      showGlobalError(error);
    }
  });
  $("#use-anvil-boss").addEventListener("click", async () => {
    try {
      if (!state.publicClient) await applyConnection();
      await connectAnvilActors($("#permissionless-account").value.trim());
      await ensurePermissionlessTokenApprovals(knownTokenAddresses());
      await refreshEverything();
    } catch (error) {
      showGlobalError(error);
    }
  });
  $("#deploy-fixtures").addEventListener("click", (event) => withBusy(event.currentTarget, async () => {
    await deployFixtures();
    await refreshEverything();
  }));
  $("#clear-fixtures").addEventListener("click", () => {
    resetFixtures();
    renderFixtures();
    refreshDomainUi().catch(showGlobalError);
  });
  $("#clear-log").addEventListener("click", () => { $("#activity-log").textContent = "Ready."; });

  const forms = [
    ["#register-token-form", registerManagedToken],
    ["#track-token-form", trackToken],
    ["#create-pricer-form", createPricer],
    ["#add-vector-form", addPricingVector],
    ["#create-quoter-form", createQuoter],
    ["#configure-rfq-form", configurePropRfq],
    ["#create-vault-form", createVault],
    ["#vault-balance-form", manageVaultBalance],
    ["#create-fee-form", createFeeConfig],
    ["#create-offer-form", createOffer],
    ["#initialize-buffer-form", initializeBuffer],
    ["#configure-buffer-form", configureBuffer],
    ["#mint-token-form", mintMockToken],
    ["#take-offer-form", takeSelectedOffer],
  ];
  forms.forEach(([selector, handler]) => bindEntityForm(selector, handler, refreshEverything));

  const offerForm = $("#create-offer-form");
  [offerForm.elements.tokenIn, offerForm.elements.tokenOut, offerForm.elements.flow].forEach((field) => {
    field.addEventListener("change", () => {
      renderSelectOptions();
      renderDerivedPricer();
    });
  });
  $("#configure-buffer-form").elements.managedToken.addEventListener("change", syncBufferForm);
  bindTransactionControls();
}

function listenToWallet(provider) {
  if (connectedWalletProvider === provider) return;
  connectedWalletProvider?.removeListener?.("accountsChanged", handleWalletAccountsChanged);
  connectedWalletProvider?.removeListener?.("chainChanged", handleWalletChainChanged);
  connectedWalletProvider = provider;
  provider.on?.("accountsChanged", handleWalletAccountsChanged);
  provider.on?.("chainChanged", handleWalletChainChanged);
}

function initializeFormDefaults() {
  const form = $("#add-vector-form");
  const base = new Date();
  const start = new Date(base.getTime() + 120_000);
  base.setSeconds(0, 0);
  start.setSeconds(0, 0);
  form.elements.baseTime.value = utcDateTimeValue(base);
  form.elements.startTime.value = utcDateTimeValue(start);
  [form.elements.baseTime, form.elements.startTime].forEach((input) => {
    input.addEventListener("input", (event) => { event.currentTarget.dataset.userEdited = "true"; });
  });
  document.querySelectorAll('[data-default="instance"]').forEach((input, index) => {
    input.value = String((Date.now() + index) % 1_000_000_000);
  });
  const initialTab = location.hash.slice(1);
  if (document.querySelector(`.tab[data-tab="${CSS.escape(initialTab)}"]`)) openTab(initialTab, renderTransactions);
}

async function syncChainTimeDefaults() {
  if (!state.publicClient) return;
  const form = $("#add-vector-form");
  const block = await state.publicClient.getBlock();
  if (form.elements.baseTime.dataset.userEdited !== "true") {
    form.elements.baseTime.value = utcDateTimeValue(new Date(Number(block.timestamp) * 1000));
  }
  if (form.elements.startTime.dataset.userEdited !== "true") {
    form.elements.startTime.value = utcDateTimeValue(new Date(Number(block.timestamp + 120n) * 1000));
  }
}

async function applyConnection() {
  configureConnection($("#rpc-url").value.trim(), $("#diamond-address").value.trim());
  await syncChainTimeDefaults();
  $("#global-message").textContent = "";
  await refreshEverything();
}

async function refreshEverything() {
  await refreshStatus();
  if (!state.diamondAddress) {
    state.latestEvents = [];
    state.discoveredRecords = [];
    renderEvents();
    await refreshDomainUi();
    return;
  }
  const code = await state.publicClient.getCode({ address: state.diamondAddress });
  if (!code || code === "0x") {
    const message = $("#global-message");
    message.textContent = "No contract code exists at the configured Diamond address.";
    message.classList.remove("hidden", "success");
    return;
  }
  await scanEventsAndRecords();
  renderEvents();
  await refreshDomainUi();
}

async function refreshStatus() {
  if (!state.publicClient) return;
  let chainId;
  let blockNumber;
  let boss;
  let permissionlessAccount;
  let code = "0x";
  try {
    [chainId, blockNumber] = await Promise.all([state.publicClient.getChainId(), state.publicClient.getBlockNumber()]);
    if (state.diamondAddress) {
      code = await state.publicClient.getCode({ address: state.diamondAddress });
      if (code && code !== "0x") {
        [boss, permissionlessAccount] = await Promise.all([
          readDiamond("boss", []),
          readDiamond("permissionlessSettlementAccount", []),
        ]);
      }
    }
  } catch (error) {
    $("#global-message").textContent = friendlyError(error);
  }

  const bossPrepared = state.bossAccount && boss && state.bossAccount.toLowerCase() === boss.toLowerCase();
  const permissionlessConfigured = permissionlessAccount && permissionlessAccount !== zeroAddress;
  const permissionlessPrepared = state.permissionlessAccount && permissionlessConfigured
    && state.permissionlessAccount.toLowerCase() === permissionlessAccount.toLowerCase();
  $("#wallet-summary").textContent = state.userAccount ? `User · ${short(state.userAccount)}` : "User wallet not connected";
  document.querySelectorAll('[data-default="account"]').forEach((input) => {
    if (state.userAccount && (!input.value || input.dataset.autofilled === "true")) {
      input.value = state.userAccount;
      input.dataset.autofilled = "true";
    }
  });
  document.querySelectorAll('[data-default="boss"]').forEach((input) => {
    if (boss && (!input.value || input.dataset.autofilled === "true")) {
      input.value = boss;
      input.dataset.autofilled = "true";
    }
  });
  if (permissionlessConfigured) $("#permissionless-account").value = permissionlessAccount;
  $("#status-grid").innerHTML = [
    statusCard("Chain", chainId ?? "offline"),
    statusCard("Block", blockNumber?.toString() ?? "—"),
    statusCard("Diamond", code && code !== "0x" ? short(state.diamondAddress) : "not deployed"),
    statusCard("User wallet", state.userAccount ? short(state.userAccount) : "not connected"),
    statusCard("Boss", boss ? `${short(boss)}${bossPrepared ? " · ready" : ""}` : "not readable"),
    statusCard("Permissionless", permissionlessConfigured
      ? `${short(permissionlessAccount)}${permissionlessPrepared ? " · ready" : ""}`
      : "not configured"),
  ].join("");
}

function renderEvents() {
  $("#event-count").textContent = `${state.latestEvents.length} events`;
  $("#events").innerHTML = state.latestEvents.length
    ? [...state.latestEvents].reverse().map((event) => `
      <div class="event-row">
        <span class="event-name">${escapeHtml(event.eventName)}</span>
        <span>block ${event.blockNumber}<br />${short(event.transactionHash)}</span>
        <code>${escapeHtml(stringify(event.args))}</code>
      </div>`).join("")
    : '<p class="muted">No decodable Diamond events found.</p>';
}

async function refreshDomainUi() {
  await hydrateDomainData();
  renderSelectOptions();
  renderOverview(renderTransactions);
  renderTokens();
  renderPricing();
  renderBuffers();
  renderQuoters();
  renderVaults();
  renderFees();
  renderOffers();
  renderTakeOfferSummary();
  await renderWalletBalances();
  renderFixtures();
  renderDerivedPricer();
  bindCopyButtons();
}
