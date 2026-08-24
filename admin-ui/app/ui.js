import { escapeHtml, friendlyError } from "./utils.js";

export const $ = (selector) => document.querySelector(selector);

export function log(message) {
  const activityLog = $("#activity-log");
  const line = `[${new Date().toISOString().slice(11, 19)} UTC] ${message}`;
  activityLog.textContent = activityLog.textContent === "Ready." ? line : `${line}\n${activityLog.textContent}`;
}

export function showGlobalError(error) {
  const globalMessage = $("#global-message");
  globalMessage.textContent = friendlyError(error);
  globalMessage.classList.remove("hidden", "success");
  log(`ERROR: ${friendlyError(error)}`);
}

export async function withBusy(button, action) {
  const globalMessage = $("#global-message");
  button.disabled = true;
  globalMessage.textContent = "";
  globalMessage.classList.add("hidden");
  try {
    await action();
  } catch (error) {
    showGlobalError(error);
  } finally {
    button.disabled = false;
  }
}

export function bindEntityForm(selector, handler, afterSuccess) {
  const form = $(selector);
  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    const button = form.querySelector("button[type=submit]");
    const result = form.querySelector(".form-result");
    button.disabled = true;
    result.className = "form-result";
    result.textContent = "Submitting transaction…";
    try {
      const message = await handler(form);
      result.classList.add("success");
      result.textContent = message || "Transaction confirmed.";
      await afterSuccess();
    } catch (error) {
      result.classList.add("error");
      result.textContent = friendlyError(error);
      log(`ERROR: ${friendlyError(error)}`);
    } finally {
      button.disabled = false;
    }
  });
}

export function openTab(name, onTransactions) {
  document.querySelectorAll(".tab").forEach((button) => button.classList.toggle("active", button.dataset.tab === name));
  document.querySelectorAll(".tab-page").forEach((page) => page.classList.toggle("active", page.dataset.page === name));
  history.replaceState(null, "", `#${name}`);
  window.scrollTo({ top: 0, behavior: "smooth" });
  if (name === "transactions") onTransactions?.();
}

export function statusCard(label, value) {
  return `<div class="status-card"><span>${label}</span><strong title="${escapeHtml(String(value))}">${escapeHtml(String(value))}</strong></div>`;
}

export function entityCard({ eyebrow, title, subtitle, status, statusClass = "", facts, id, idLabel }) {
  return `<article class="entity-card">
    <div class="entity-card-header"><div><p class="eyebrow">${escapeHtml(eyebrow)}</p><h3>${escapeHtml(title)}</h3><p class="entity-subtitle">${escapeHtml(subtitle || "")}</p></div><span class="tag ${statusClass}">${escapeHtml(status)}</span></div>
    <dl class="facts">${facts.map(([label, value]) => `<div class="fact"><dt>${escapeHtml(label)}</dt><dd>${escapeHtml(String(value))}</dd></div>`).join("")}</dl>
    <details class="technical"><summary>Technical identifier</summary><code>${escapeHtml(String(id))}</code><div class="entity-actions"><button type="button" data-copy="${escapeHtml(String(id))}">Copy ${escapeHtml(idLabel)}</button></div></details>
  </article>`;
}

export function emptyState(message) {
  return `<div class="empty-state">${escapeHtml(message)}</div>`;
}

export function bindCopyButtons() {
  document.querySelectorAll("[data-copy]").forEach((button) => button.addEventListener("click", async () => {
    await navigator.clipboard.writeText(button.dataset.copy);
    const original = button.textContent;
    button.textContent = "Copied";
    setTimeout(() => { button.textContent = original; }, 900);
  }));
}
