import { advancedMethods, diamondAbi } from "./config.js";
import { readDiamond, writeBossDiamond } from "./chain.js";
import { $, log } from "./ui.js";
import { escapeHtml, exampleValue, friendlyError, parseAbiInput, stringify } from "./utils.js";

export function initializeAdvancedConsole(afterWrite) {
  const functions = diamondAbi.filter((item) => item.type === "function");
  const reads = functions.filter((item) => item.stateMutability === "view" || item.stateMutability === "pure");
  const writes = functions.filter((item) => item.stateMutability === "nonpayable" || item.stateMutability === "payable");
  $("#read-methods").innerHTML = reads.map((item) => methodCard(item, "read")).join("");
  $("#write-methods").innerHTML = writes.map((item) => methodCard(item, "write")).join("");
  document.querySelectorAll(".method-card form").forEach((form) => {
    form.addEventListener("submit", (event) => executeMethod(event, afterWrite).catch((error) => showMethodError(form, error)));
  });
  $("#read-filter").addEventListener("input", () => filterCards("read"));
  $("#write-filter").addEventListener("input", () => filterCards("write"));
}

function methodCard(item, mode) {
  const signature = `${item.name}(${item.inputs.map((input) => input.type).join(", ")})`;
  const inputs = item.inputs.map((input, index) => inputField(input, index)).join("");
  const advanced = advancedMethods.has(item.name) ? "advanced" : "";
  return `
    <article class="method-card ${advanced}" data-mode="${mode}" data-name="${item.name.toLowerCase()}">
      <div><h3>${item.name}</h3><div class="signature">${escapeHtml(signature)}</div></div>
      <form data-function="${item.name}" data-mode="${mode}">
        ${inputs}
        <button type="submit" class="${mode === "write" ? "primary" : ""}">${mode === "write" ? "Simulate and send" : "Read"}</button>
      </form>
      <pre class="result hidden"></pre>
    </article>`;
}

function inputField(input, index) {
  const isComplex = input.type.startsWith("tuple") || input.type.includes("[");
  const example = exampleValue(input);
  const placeholder = isComplex ? stringify(example) : typeof example === "string" ? example : String(example);
  const field = isComplex
    ? `<textarea name="arg-${index}" placeholder="${escapeHtml(placeholder)}">${escapeHtml(placeholder)}</textarea>`
    : `<input name="arg-${index}" value="${escapeHtml(placeholder)}" autocomplete="off" />`;
  return `<label>${escapeHtml(input.name || `arg${index}`)} <code>${escapeHtml(input.type)}</code>${field}</label>`;
}

async function executeMethod(event, afterWrite) {
  event.preventDefault();
  const form = event.currentTarget;
  const item = diamondAbi.find((candidate) => candidate.type === "function" && candidate.name === form.dataset.function);
  const args = item.inputs.map((input, index) => parseAbiInput(input, form.elements[`arg-${index}`].value));
  const button = form.querySelector("button[type=submit]");
  const result = form.closest(".method-card").querySelector(".result");
  button.disabled = true;
  result.classList.remove("hidden", "error");
  result.textContent = form.dataset.mode === "read" ? "Reading…" : "Simulating…";
  try {
    if (form.dataset.mode === "read") {
      result.textContent = stringify(await readDiamond(item.name, args));
    } else {
      result.textContent = stringify(await writeBossDiamond(item.name, args));
      await afterWrite();
    }
  } finally {
    button.disabled = false;
  }
}

function filterCards(mode) {
  const query = $(`#${mode}-filter`).value.trim().toLowerCase();
  document.querySelectorAll(`.method-card[data-mode="${mode}"]`).forEach((card) => {
    card.classList.toggle("hidden", !card.dataset.name.includes(query));
  });
}

function showMethodError(form, error) {
  const result = form.closest(".method-card").querySelector(".result");
  result.classList.remove("hidden");
  result.classList.add("error");
  result.textContent = friendlyError(error);
  log(`ERROR ${form.dataset.function}: ${friendlyError(error)}`);
}
